require 'openstudio'
require 'csv'

class OccupancyBasedThermostat < OpenStudio::Measure::ModelMeasure

  # human readable name
  def name
    return "Occupancy-Based Thermostats"
  end

  # human readable description
  def description
    return "Adjust thermostats based on a master occupancy schedule file."
  end

  # human readable description of modeling approach
  def modeler_description
    return \
      "For each zone in the model that matches the specified zones and has a " \
      "thermostat with both heating and cooling schedules, apply a symmetric " \
      "offset to the heating and cooling setpoints based on a occupancy " \
      "schedule file and occupant threshhold below which the offset will " \
      "be applied. Overwrites all applicable thermostat schedules with " \
      "schedule files."
  end

  # define the arguments the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    arg = OpenStudio::Measure::OSArgument::makeStringArgument(
      "occupancy_schedule"
    )
    arg.setDisplayName("Occupancy Schedule Name")
    arg.setDescription("Name of schedule to pull occupancies from.")
    arg.setUnits("#")
    arg.setDefaultValue("occupants")
    args << arg

    arg = OpenStudio::Measure::OSArgument::makeDoubleArgument(
      "occupancy_threshold"
    )
    arg.setDisplayName("Occupancy Threshold For Setback")
    arg.setDescription(
      "Occupancy threshold below which to apply offset. Should be in [0, 100]."
    )
    arg.setUnits("%")
    arg.setDefaultValue(10.0)
    args << arg

    arg = OpenStudio::Measure::OSArgument::makeDoubleArgument("heating_setpoint")
    arg.setDisplayName("Heating Setpoint")
    arg.setDescription("TODO")
    arg.setUnits("degrees F")
    arg.setDefaultValue(71.0)
    args << arg

    arg = OpenStudio::Measure::OSArgument::makeDoubleArgument("cooling_setpoint")
    arg.setDisplayName("Cooling Setpoint")
    arg.setDescription("TODO")
    arg.setUnits("degrees F")
    arg.setDefaultValue(76.0)
    args << arg

    arg = OpenStudio::Measure::OSArgument::makeDoubleArgument(
      "thermostat_offset"
    )
    arg.setDisplayName("Thermostat Offset")
    arg.setDescription(
      "Temperature offset to apply to both the heating and cooling setpoints."
    )
    arg.setUnits("R")
    arg.setDefaultValue(5)
    args << arg

    arg = OpenStudio::Measure::OSArgument::makeStringArgument("zone_names")
    arg.setDisplayName("Zone Names")
    arg.setDescription(
      "Comma-separated string of thermal zone names to apply the offsets to."
    )
    args << arg

    return args
  end

  # define what happens when the measure is run.
  def run(model, runner, user_arguments)
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    occupancy_schedule_name = runner.getStringArgumentValue(
      'occupancy_schedule', user_arguments
    )
    occupancy_threshold = \
      runner.getDoubleArgumentValue('occupancy_threshold', user_arguments) / 100
    cooling_setpoint = runner.getDoubleArgumentValue(
      'cooling_setpoint', user_arguments)
    heating_setpoint = runner.getDoubleArgumentValue(
      'heating_setpoint', user_arguments)
    offset = runner.getDoubleArgumentValue(
      'thermostat_offset', user_arguments)
    target_zones = runner.getStringArgumentValue(
      'zone_names', user_arguments).split(',')

    # For every zone in the model, get its thermostat and occupancy schedule (if
    # any)
    offset_c = OpenStudio.convert(offset, "R", "K").get.round(1)
    cooling_c = OpenStudio.convert(cooling_setpoint, "F", "C").get.round(1)
    heating_c = OpenStudio.convert(heating_setpoint, "F", "C").get.round(1)

    zones_changed = []

    occupancy_schedule = model.getScheduleByName(occupancy_schedule_name).get
    load_schedule_file(occupancy_schedule.to_ScheduleFile.get)

    model.getThermalZones.each do |zone|
      # Skip zones that don't match our name checking.
      zone_name = zone.name.get
      next if zone_name.nil?
      unless target_zones.include? zone_name
        runner.registerInfo("Skipping zone #{zone_name}")
        next
      end

      # TODO: Add some logging here
      next if zone.thermostat.empty?
      next if zone.thermostat.get.to_ThermostatSetpointDualSetpoint.empty?

      thermostat = zone.thermostat.get.to_ThermostatSetpointDualSetpoint.get

      # Skip thermostats that don't have both heating and cooling schedules
      if thermostat.heatingSetpointTemperatureSchedule.empty? || \
          thermostat.coolingSetpointTemperatureSchedule.empty?
        runner.registerInfo(
          "Zone #{zone.name} is missing either a heating or cooling " \
          "schedule, predictive thermostat not applicable."
        )
      end

      new_heating, new_cooling = create_predictive_thermostat_schedule(
        model, runner, occupancy_schedule, occupancy_threshold,
        heating_c, cooling_c, offset_c
      )

      thermostat.setHeatingSetpointTemperatureSchedule(new_heating)
      thermostat.setHeatingSetpointTemperatureSchedule(new_cooling)
      zones_changed << zone

      runner.registerInfo("Adjusted thermostat for #{zone_name}")
    end

    if zones_changed.size == 0
      runner.registerAsNotApplicable("No zone thermostats were modified.")
    end
    runner.registerFinalCondition(
      "#{zones_changed.size} zones were adjusted."
    )
    return true
  end

  # Parse the occupant schedule and create the thermostat schedule appropriately.
  def create_predictive_thermostat_schedule(
    model, runner, occupant_schedule, occupancy_threshold, heating_temp,
    cooling_temp, offset
  )
    if occupant_schedule.to_ScheduleFile.empty?
      puts "errore!!!"
      return false
    end
    occupant_schedule = occupant_schedule.to_ScheduleFile.get

    occupancies = load_schedule_file(occupant_schedule)
    heatings = OpenStudio::Vector.new(occupancies.length)
    coolings = OpenStudio::Vector.new(occupancies.length)
    occupancies.each_with_index do |occupancy, i|
      if occupancy <= occupancy_threshold
        heatings[i] = heating_temp - offset
        coolings[i] = cooling_temp + offset
      else
        heatings[i] = heating_temp
        coolings[i] = cooling_temp
      end
    end

    # Write out the vectors to a new CSV
    schedule_path = "../thermostat_schedules.csv"
    CSV.open(schedule_path, 'w') do |csv|
      csv << ["heating_setpoint", "cooling_setpoint"]
      (0..heatings.length).each do |i|
        csv << [heatings[i], coolings[i]]
      end
    end
    external_file = OpenStudio::Model::ExternalFile.getExternalFile(
      model, File.realpath(schedule_path)
    ).get
    heating_schedule = OpenStudio::Model::ScheduleFile.new(
      external_file, 1, 1
    )
    cooling_schedule = OpenStudio::Model::ScheduleFile.new(
      external_file, 2, 0
    )
    return heating_schedule, cooling_schedule
  end

  # Given an OpenStudio schedule file, return an OpenStudio vector of the vals.
  def load_schedule_file(schedule)
    raw_data = CSV.table(schedule.externalFile.filePath.to_s)
    # Indexing starts at 1
    column = schedule.columnNumber - 1
    rows_to_skip = schedule.rowstoSkipatTop

    num_values = (
      schedule.numberofHoursofData.get * 60 / schedule.minutesperItem.get.to_i
    ).to_i
    occupancy = OpenStudio::Vector.new(num_values)

    raw_data.each_with_index do |row, i|
      next if i < rows_to_skip
      occupancy[i] = row[column]
    end
    return occupancy
  end
end

OccupancyBasedThermostat.new.registerWithApplication

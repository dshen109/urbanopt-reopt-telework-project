# Generate scenario JSON and CSV files to automate runs.
import copy
import csv
import json
import subprocess
import sys

TEMPLATE_DIRECTORY = "./templates"

with open("./templates/default_building.json", "r") as f:
    DEFAULT_BUILDING = json.load(f)

with open("./reopt/base_assumptions.json", "r") as f:
    DEFAULT_REOPT = json.load(f)

class Simulation:
    """
    Store simulation parameters & run simulations.

    Adjustable parameters:
        - latitude
        - longitude
        - floor_area
        - footprint_area
        - number_of_stories_above_ground
        - number_of_stories
        - number_of_bedrooms
        - foundation_type
        - attic_type
        - system_type
        - template
        - schedules_type
        - num_buildings (number of times to run Monte Carlo simulation)
        - climate_zone
        - default_template
        - weatherfile
        - timesteps_per_hour
    """

    def __init__(
            self, location, building_parameters, reopt_parameters,
            weatherfile, climate_zone, latitude, longitude, num_simulations=1,
            timesteps_per_hour=1, tag=""):
        """
        :param dict location: human-readable location
        :param dict building_parameters: Building parameters
        :param dict reopt_parameters: REopt parameters
        :param str weatherfile: EPW filename
        :param str climate_zone: climate zone
        :param float latitude: site latitude
        :param float longitude: site longitude
        :param int num_buildings: number of simulations to run with the building
            parameters
        :param int timesteps_per_hour: Number of timesteps per hour
        :param str tag: Tag to add to produced files.
        """
        self.location = location
        self.building_parameters = building_parameters
        self.reopt_parameters = reopt_parameters
        self.weatherfile = weatherfile
        self.climate_zone = climate_zone
        self.latitude = latitude
        self.longitude = longitude
        self.num_simulations = num_simulations
        self.timesteps_per_hour = timesteps_per_hour
        self.tag = tag

    @classmethod
    def from_json(cls, filepath):
        with open(filepath, "r") as f:
            data = json.load(f)
        try:
            return cls(
                data["location"],
                data["building"], data["reopt"], data["weatherfile"],
                data["climate_zone"], data["latitude"], data["longitude"],
                data.get("num_simulations", 1),
                data.get("timesteps_per_hour", 1), data.get("tag")
            )
        except KeyError as e:
            raise ValueError from e

    @classmethod
    def from_dict(cls, dictionary):
        try:
            return cls(
                dictionary["location"],
                dictionary["building"], dictionary["reopt"],
                dictionary["weatherfile"], dictionary["climate_zone"],
                dictionary["latitude"], dictionary["longitude"],
                dictionary.get("num_simulations", 1),
                dictionary.get("timesteps_per_hour", 1), dictionary.get("tag")
            )
        except KeyError as e:
            raise ValueError from e


    def make_scenario_json(self):
        """
        Make a scenario json
        """
        scenario = {
            "type": "FeatureCollection",
            "project": {
                "id": "some-id-i-guess",
                "name": "New Project",
                "surface_elevation": None,
                "import_surrounding_buildings_as_shading": None,
                "weather_filename": self.weatherfile,
                "tariff_filename": None,
                "climate_zone": self.climate_zone,
                "cec_climate_zone": None,
                # TODO: Check if we need to set these times properly...
                "begin_date":"2007-01-01T07:00:00.000Z",
                "end_date":"2007-12-31T07:00:00.000Z",
                "timesteps_per_hour": self.timesteps_per_hour,
                "default_template":"90.1-2013"
            },
            "features": [
                {
                    "type": "Feature",
                    "properties": {
                        "id": "correcthorsebattery",
                        "name": "Site Origin",
                        "type": "Site Origin"
                    },
                    "geometry": {
                        "type": "Point",
                        "coordinates": [
                            self.latitude,
                            self.longitude
                        ]
                    }
                }
            ],
            "mappers": [],
            "scenarios": [
                {
                    "feature_mappings": [],
                    "id": "another-dummy-id",
                    "name": "New Scenario"
                }
            ]
        }
        for i in range(1, self.num_simulations + 1):
            scenario["features"].append(self.make_building_feature(i))
        return scenario

    def write_scenario_json(self):
        """
        Write a JSON scenario file.
        """
        with open(self.scenario_filename, "w+") as f:
            json.dump(self.make_scenario_json(), f, indent=2)
        print(f"Wrote scenario JSON to {self.scenario_filename}")
        return self.scenario_filename

    def write_mapper_csv(self):
        """
        Write a mapper CSV file.
        """
        with open(self.mapper_filename, "w+") as f:
            writer = csv.writer(f)
            writer.writerow([
                "Feature ID", "Feature Name", "Mapper Class",
                "REopt Assumptions"
                ])
            for i in range(1, self.num_simulations + 1):
                writer.writerow([
                    str(i), f"Residential {i}",
                    "URBANopt::Scenario::BaselineMapper",
                    self.reopt_filename
                ])
        print(f"Wrote mapper CSV to {self.mapper_filename}")
        return self.mapper_filename

    def write_reopt_json(self):
        """
        Write the REopt JSON.
        """
        template = copy.deepcopy(DEFAULT_REOPT)
        site = template["Scenario"]["Site"]

        for k, v in self.reopt_parameters["Scenario"]["Site"].items():
            site[k].update(v)

        template["Scenario"]["time_steps_per_hour"] = self.timesteps_per_hour

        with open(f"./reopt/{self.reopt_filename}", "w+") as f:
            json.dump(template, f, indent=2)
        print(f"Wrote reopt assumptions to ./reopt/{self.reopt_filename}")
        return self.reopt_filename

    def make_geojson_polygon(self):
        """
        Return a dummy array of GeoJson coordinates since URBANopt won't accept a
        point for buildings.
        """
        return [[
            [self.latitude, self.longitude],
            [self.latitude, self.longitude + 0.0005],
            [self.latitude + 0.0005, self.longitude + 0.0005],
            [self.latitude + 0.0005, self.longitude]
        ]]

    def make_building_feature(self, number):
        """
        Return a dictionary representing a building feature.
        """
        output = {
            "type": "Feature",
            "properties": {
                "id": f"{number}", "name": f"Residential {number}",
                "type": "Building"
            },
            "geometry": {
                "type": "Polygon",
                "coordinates": self.make_geojson_polygon()
            }
        }
        # Populate with the scenario properties, but fall back to defaults if
        # necessary.
        for key in DEFAULT_BUILDING.keys():
            output["properties"][key] = getattr(self, key)
        return output

    @property
    def mapper_filename(self):
        return TEMPLATE_DIRECTORY + "/" + self.base_filename + ".csv"

    @property
    def scenario_filename(self):
        return TEMPLATE_DIRECTORY + "/" + self.base_filename + ".json"

    @property
    def reopt_filename(self):
        return "reopt-" + self.base_filename + ".json"

    @property
    def base_filename(self):
        if not self.tag:
            return \
                f"res-scenario-" \
                f"{self.schedules_type}-schedule-{self.timesteps_per_hour}-" \
                f"steps-{self.location.lower().replace(' ', '-')}"
        else:
            return self.tag

    def __getattr__(self, key):
        """
        Try and get attributes from the building_parameters, but fallback on the
        default values.
        """
        try:
            return self.building_parameters[key]
        except KeyError:
            try:
                return DEFAULT_BUILDING[key]
            except KeyError:
                pass

        return object.__getattribute__(self, key)

    def clear_and_run(self):
        """
        Run rake task.
        """
        try:
            print("Clearing old simulation files...")
            clearing = subprocess.check_output(
                [
                    "bundle", "exec", "rake",
                    f"clear_baseline[{self.scenario_filename}," \
                        f"{self.mapper_filename}]",
                ], cwd="../"
            )
            print(clearing.decode('utf-8'))
            print("Old files cleared!")

            print("Starting simulation rake task...")
            running = subprocess.check_output(
                [
                    "bundle", "exec", "rake",
                    f"run_baseline[{self.scenario_filename}," \
                        f"{self.mapper_filename}]",
                ], cwd="../"
            )
            print(running.decode('utf-8'))
            print("Finished simulation!")

            print("Starting REopt optimization...")
            reopting = subprocess.check_output(
                [
                    "bundle", "exec", "rake",
                    f"post_process_baseline[{simulation.scenario_filename}," \
                        f"{simulation.mapper_filename}]",
                ], cwd="../"
            )
            print(reopting.decode('utf-8'))
            print("Finished REopt optimization!")
            # Move the scenario JSON into the run folder so it's traceable.
            subprocess.run(
                [
                    "mv", f"{self.scenario_filename}",
                    f"run/{self.base_filename}/"
                ]
            )
        except:
            print("error running task")
            # Delete the created files.
            subprocess.run(["rm", f"{self.mapper_filename}"], cwd=".")
            subprocess.run(["rm", f"{self.scenario_filename}"], cwd=".")
            subprocess.run(["rm", f"reopt/{self.reopt_filename}"], cwd=".")


if __name__ == "__main__":
    args = sys.argv[1:]
    if args:
        template = sys.argv[1]
    else:
        raise RuntimeError("No template supplied.")
    simulation = Simulation.from_json(template)
    simulation.write_mapper_csv()
    simulation.write_scenario_json()
    simulation.write_reopt_json()

    simulation.clear_and_run()

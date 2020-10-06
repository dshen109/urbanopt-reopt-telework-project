# Generate scenario JSON and CSV files to automate runs.
import copy
import csv
import json
import subprocess

DEFAULT_BUILDING = {
    "type": "Building",
    "building_type": "Single-Family Detached",
    "floor_area": 2301,
    "footprint_area": 2301,
    "number_of_stories_above_ground": 1,
    "number_of_stories": 1,
    "number_of_bedrooms": 3,
    "foundation_type": "slab",
    "attic_type": "attic - vented",
    "system_type":
        "Residential - electric resistance and central air conditioner",
    "template":
        "Residential IECC 2015 - Customizable Template Sep 2020",
    "schedules_type": "default"
}

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
            timesteps_per_hour=1):
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
                data.get("timesteps_per_hour", 1)
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
        return self.base_filename + ".csv"

    @property
    def scenario_filename(self):
        return self.base_filename + ".json"

    @property
    def reopt_filename(self):
        return "reopt-" + self.base_filename + ".json"

    @property
    def base_filename(self):
        return \
            f"residential-scenario-" \
            f"{self.schedules_type}-schedule-{self.timesteps_per_hour}-steps-" \
            f"{self.location.lower().replace(' ', '-')}"

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


if __name__ == "__main__":
    simulation = Simulation.from_json("phoenix-demand-template.json")
    simulation.write_mapper_csv()
    simulation.write_scenario_json()
    simulation.write_reopt_json()

    try:
        print("Starting simulation rake task...")
        subprocess.check_output(
            [
                "bundle", "exec", "rake",
                f"run_baseline[{simulation.scenario_filename}," \
                    f"{simulation.mapper_filename}]",
            ], cwd="../"
        )
        print("Finished simulation!")

        print("Starting REopt optimization...")
        subprocess.check_output(
            [
                "bundle", "exec", "rake",
                f"post_process_baseline[{simulation.scenario_filename}," \
                    f"{simulation.mapper_filename}]",
            ], cwd="../"
        )
        print("Finished REopt optimization!")
    except:
        print("error running task")


"""
Functionality to aid in processing results.
"""
import functools
from glob import glob
import re
import os
import pandas as pd
import ujson as json


class Results:

    def __init__(self, results_dir, run_dir):
        """
        :param str results_dir: REopt output folder
        :param str run_dir: URBANopt output folder
        """
        # Keyed by the filepath of the REopt run JSON
        self._results = {}
        self.results_dir = results_dir
        self.run_dir = run_dir
        self._scenarios = {}

    def to_dataframe(self, selections={}, scenarios=[]):
        """
        :param dict selections: key value pair of column and column values that
            must be satisfied, e.g. {"location": "San Diego"} will only return
            entries in San Diego.
        :param lst scenarios: List of scenario IDs that must be matched
        """
        frame = pd.DataFrame.from_dict(self._results, orient='index')

        if scenarios:
            indices = []
            for scenario_id in scenarios:
                indices.append(frame['scenario_id'] == scenario_id)
            frame = frame.loc[
                functools.reduce(lambda x, y: x | y, indices)
            ]

        # Select columns that match all the criteria.
        if selections:
            for k, v in selections.items():
                frame = frame.loc[frame[k] == v]
        return frame

    def to_scenario_dataframe(self, selections={}):
        """
        Return DataFrame of scenario data matching the parameters in *selections*
        """
        # TODO: Implement this.
        pass

    def load(self, scenario_pattern="", reopt_pattern="",
             default_schedules_only=False):
        """
        Load all results from the REopt and scenario directory.

        :param str default_schedules_only: Only load results with `default` in
            the filepath
        :param str scenario_pattern: Pattern matching for the scenario
        :param str reopt_pattern: Pattern matching for reopt
        """
        scenarios = os.listdir(self.results_dir)
        for scenario in scenarios:
            if scenario_pattern and re.match(scenario_pattern, scenario) is None:
                continue
            elif "default" not in scenario and default_schedules_only:
                continue
            print(f'loading runs for {scenario}...')
            self.load_reopt_runs(scenario, reopt_pattern)

    def load_reopt_runs(self, scenario_id, reopt_pattern=""):
        """
        Load all reopt runs associated with the scenario ID.

        :param str reopt_pattern: Regex matching for fill reopt filepath.
        """
        reopt_scenario_dir = os.path.join(self.results_dir, scenario_id)

        scenario_params = self.load_scenario(scenario_id)

        for reopt_run in sorted(
                self.get_leaf_jsons(reopt_scenario_dir)):
            if reopt_pattern and re.match(reopt_pattern, reopt_run) is None:
                continue

            if reopt_run in self._results:
                continue

            with open(reopt_run, "r") as f:
                reopt_results = json.load(f)

            building_id = os.path.split(os.path.split(reopt_run)[0])[1]

            self._results[reopt_run] = {
                **scenario_params, **self.extract_reopt_metrics(reopt_results),
                "building_id": building_id, "scenario_id": scenario_id
            }

    @staticmethod
    def get_leaf_jsons(path):
        return [y for x in os.walk(path) for y in glob(os.path.join(x[0], '*.json'))]

    def load_scenario(self, scenario):
        """
        Given a scenario ID, e.g.
        home-san-diego-3-bd-2301-sched-stochastic-9542565323, return information
        from the URBANopt scenario file.

        Also do caching of scenario parameters.
        """
        if scenario in self._scenarios:
            return self._scenarios[scenario]

        with open(os.path.join(self.run_dir, scenario, "urbanopt_scenario.json"), "r") as f:
            scenario_params = self.extract_scenario_params(json.load(f))
        self._scenarios[scenario] = scenario_params
        return scenario_params

    @staticmethod
    def extract_scenario_params(scenario_json):
        """
        "type": "Building",
        "building_type": "Single-Family Detached",
        "floor_area": 2301,
        "footprint_area": 2301,
        "number_of_stories_above_ground": 1,
        "number_of_stories": 1,
        "number_of_bedrooms": 3,
        "foundation_type": "slab",
        "attic_type": "attic - vented",
        "system_type": "Residential - electric resistance and central air conditioner",
        "template": "Residential IECC 2015 - Customizable Template Sep 2020",
        "schedules_type": "default"
        """
        schedules_type = scenario_json['features'][1]['properties']['schedules_type']
        floor_area = scenario_json['features'][1]['properties']['floor_area']
        climate_zone = scenario_json['project']['climate_zone']
        weatherfile = scenario_json['project']['weather_filename']
        location = scenario_json['project']['name']
        # Subtract 1 since the first feature is the site origin.
        num_simulations = len(scenario_json['features']) - 1
        timesteps_per_hour = scenario_json['project']['timesteps_per_hour']
        latitude = scenario_json['features'][0]['geometry']['coordinates'][0]
        longitude = scenario_json['features'][0]['geometry']['coordinates'][1]

        return {
            "schedules_type": schedules_type,
            "floor_area": floor_area,
            "climate_zone": climate_zone,
            "weatherfile": weatherfile,
            "location": location,
            "num_simulations": num_simulations,
            "timesteps_per_hour": timesteps_per_hour,
            "latitude": latitude,
            "longitude": longitude,
        }

    @staticmethod
    def extract_reopt_metrics(reopt_json, load_series=False):
        """
        Get useful metrics.

        :param bool load_series: Load the timeseries data
        :return: dictionary
        """
        output_site = reopt_json['outputs']['Scenario']['Site']
        input_site = reopt_json['inputs']['Scenario']['Site']

        pv_size = output_site['PV']['size_kw']
        storage_size_kw = output_site['Storage']['size_kw']
        storage_size_kwh = output_site['Storage']['size_kwh']
        load_annual_kwh = output_site['LoadProfile']['annual_calculated_kwh']
        savings = output_site['Financial']['npv_us_dollars']
        pv_yearly_energy_produced = \
            output_site['PV']['average_yearly_energy_produced_kwh']
        pv_energy_exported = \
            output_site['PV']['average_yearly_energy_exported_kwh']


        if load_series:
            load_profile = output_site['LoadProfile']['year_one_electric_load_series_kw']
            pv_power_production = output_site['PV']['year_one_power_production_series_kw']
            pv_to_battery = output_site['PV']['year_one_to_battery_series_kw']
            pv_to_load = output_site['PV']['year_one_to_load_series_kw']
            pv_to_grid = output_site['PV']['year_one_to_grid_series_kw']
            pv_curtailed = output_site['PV']['year_one_curtailed_production_series_kw']
            storage_to_load = output_site['Storage']['year_one_to_load_series_kw']
            storage_to_grid = output_site['Storage']['year_one_to_grid_series_kw']
        else:
            load_profile = None
            pv_power_production = None
            pv_to_battery = None
            pv_to_load = None
            pv_to_grid = None
            pv_curtailed = None
            storage_to_load = None
            storage_to_grid = None


        urdb = input_site['ElectricTariff']['urdb_response']['label']
        utility = input_site['ElectricTariff']['urdb_utility_name']
        rate_name = input_site['ElectricTariff']['urdb_rate_name']
        net_metering_limit = input_site['ElectricTariff']['net_metering_limit_kw']
        storage_rebate = input_site['Storage']['total_rebate_us_dollars_per_kwh']

        timesteps_per_hour = reopt_json['inputs']['Scenario']['time_steps_per_hour']


        return {
            "pv_size": pv_size,
            "pv_power_production": pv_power_production,
            "pv_to_battery": pv_to_battery,
            "pv_to_load": pv_to_load,
            "pv_to_grid": pv_to_grid,
            "pv_curtailed": pv_curtailed,
            "pv_yearly_energy_produced": pv_yearly_energy_produced,
            "pv_energy_exported": pv_energy_exported,
            "storage_size_kw": storage_size_kw,
            "storage_size_kwh": storage_size_kwh,
            "storage_to_load": storage_to_load,
            "storage_to_grid": storage_to_grid,
            "load_profile": load_profile,
            "load_annual_kwh": load_annual_kwh,
            "urdb": urdb,
            "utility": utility,
            "rate_name": rate_name,
            "net_metering_limit": net_metering_limit,
            "storage_rebate": storage_rebate,
            "timesteps_per_hour": timesteps_per_hour,
            "savings": savings
        }

    def get_scenario_electricity_usage(
            self, location, schedules_type="default", building_num=1,
            num_simulations=1):
        """
        Get electricity usage data for the described scenario.
        """
        params = {
            "location": location,
            "schedules_type": schedules_type,
            "building_num": building_num,
        }
        for scenario in self.get_matching_scenarios(params):
            # Check if it matches
            scenario_params = self.load_scenario(scenario)
            # Load up the electricity file.
            report_csv = os.path.join(
                self.run_dir, scenario, str(building_num),
                "014_default_feature_reports", "default_feature_reports.csv")
            try:
                report = pd.read_csv(
                    report_csv, index_col=0, infer_datetime_format=True,
                    parse_dates=True
                )
            except FileNotFoundError as e:
                # Probably because the building number doesn't exist
                raise FileNotFoundError(f"No building number {building_num}") from e
            # Check and make sure the timestep matches what we expect.
            report_timestep = (report.index[1] - report.index[0]).total_seconds()
            if not (3600 / scenario_params["timesteps_per_hour"] == report_timestep):
                raise RuntimeError(
                    "Mismatch in simulated timestep vs. scenario timestep, "
                    f"building {building_num} of {self.scenario_name}")

            electricity_cols = [
                c for c in report.columns if "kWh" in c and "Electricity" in c
                and ":" in c
            ]

            return report[electricity_cols]

        raise FileNotFoundError(
            f"No scenario with location {location} found that satisfies "
            f"schedules_type={schedules_type}, building_num={building_num}",
            f"num_simulations={num_simulations}")

    def get_scenario_schedule(self, location, building_num=1, num_simulations=1):
        """
        Get the occupant schedule associated with the keyword descriptors.
        """
        params = {
            "location": location,
            "schedules_type": "stochastic",
            "building_num": building_num,
        }
        for scenario in self.get_matching_scenarios(params):
            # Load up the schedule file.
            report_csv = os.path.join(
                self.run_dir, scenario, str(building_num),
                "schedules.csv")
            try:
                report = pd.read_csv(report_csv)
            except FileNotFoundError:
                continue

            index = self.get_scenario_electricity_usage(
                location, 'stochastic', building_num=building_num,
                num_simulations=num_simulations).index

            report.index = index

            return report

        raise FileNotFoundError(
            f"No scenario with location {location} found that satisfies "
            f"building_num={building_num}, num_simulations={num_simulations}")

    def get_matching_scenarios(self, params=None):
        """
        Only get scenarios IDs that match the specified parameter(s). If None,
        return all scenarios.

        :param dict parameters: Dictionary of scenario parameters that must
            match. If the values are a list, will consider the scenario to
            be a match if it matches at least one of the list entries.
        :return: List of scenario IDs that match.
        """
        matches = []
        for scenario in os.listdir(self.run_dir):
            match = True
            if params:
                scenario_params = self.load_scenario(scenario)
                for k, v in params.items():
                    if k == "building_num":
                        continue
                    elif isinstance(v, (int, float, str)):
                        if scenario_params[k] != v:
                            match = False
                            break
                    else:
                        # If we're given a list of choices, handle those.
                        any_match = False
                        for choice in v:
                            if scenario_params[k] == choice:
                                any_match = True
                                break
                        if not any_match:
                            match = False
                            break
            if match:
                matches.append(scenario)
        return matches

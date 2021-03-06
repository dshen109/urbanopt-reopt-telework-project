# Generate scenario JSON and CSV files to automate runs.
import argparse
import copy
import csv
import datetime
import errno
import json
import hashlib
import os
import re
import subprocess
import sys
import threading
import time

import pandas as pd
import pytz
import requests
from requests.packages.urllib3.exceptions import InsecureRequestWarning

from templates.generate_templates import TEMPLATE_DIRECTORY, flatten_dict

# Warnings from REopt calls.
requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

TEMPLATE_DIRECTORY = f"./templates/{TEMPLATE_DIRECTORY}"

REOPT_RESULTS_PATH = "./reopt_results"

DEFAULT_REOPT_URL = 'https://developer.nrel.gov/api/reopt'

REOPT_URL = os.environ.get('REOPT_URL', DEFAULT_REOPT_URL)

# Lock for number of active threads.
thread_lock = threading.Lock()
REOPT_THREAD_COUNTER = 0

with open("./templates/default_building.json", "r") as f:
    DEFAULT_BUILDING = json.load(f)

with open("./reopt/base_assumptions.json", "r") as f:
    DEFAULT_REOPT = json.load(f)


def log(*args, **kwargs):
    return print(*args, **kwargs)


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
            weatherfile, climate_zone, latitude, longitude, timezone,
            num_simulations=1, scenario_timesteps_per_hour=1, tag=""):
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
        :param str tag: Tag to name the produced files.
        """
        self.location = location
        self.building_parameters = building_parameters
        self.reopt_parameters = reopt_parameters
        self.weatherfile = weatherfile
        self.climate_zone = climate_zone
        self.latitude = latitude
        self.longitude = longitude
        self.num_simulations = num_simulations
        self.scenario_timesteps_per_hour = scenario_timesteps_per_hour
        # TODO: make this settable somehow...
        self.reopt_timesteps_per_hour = 1
        self.tag = tag
        self.timezone = timezone

    @classmethod
    def from_json(cls, filepath):
        with open(filepath, "r") as f:
            data = json.load(f)
        try:
            return cls.from_dict(data)
        except KeyError as e:
            raise ValueError from e

    @classmethod
    def from_dict(cls, dictionary):
        try:
            return cls(
                location=dictionary["location"],
                building_parameters=dictionary["building"],
                reopt_parameters=dictionary["reopt"],
                weatherfile=dictionary["weatherfile"],
                climate_zone=dictionary["climate_zone"],
                latitude=dictionary["latitude"],
                longitude=dictionary["longitude"],
                num_simulations=dictionary.get("num_simulations", 1),
                scenario_timesteps_per_hour=\
                    dictionary.get("timesteps_per_hour", 1),
                tag=dictionary.get("tag"),
                timezone=dictionary['timezone'],
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
                "name": f"{self.location}",
                "surface_elevation": None,
                "import_surrounding_buildings_as_shading": None,
                "weather_filename": self.weatherfile,
                "tariff_filename": None,
                "climate_zone": self.climate_zone,
                "cec_climate_zone": None,
                "begin_date": self.begin_date,
                "end_date": self.end_date,
                "timesteps_per_hour": self.scenario_timesteps_per_hour,
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
        log(f"Wrote scenario JSON to {self.scenario_filename}")
        return self.scenario_filename

    def write_mapper_csv(self):
        """
        Write a mapper CSV file.
        """
        with open(self.mapper_filename, "w+") as f:
            writer = csv.writer(f)
            writer.writerow([
                "Feature ID", "Feature Name", "Mapper Class"
                ])
            for i in range(1, self.num_simulations + 1):
                writer.writerow([
                    str(i), f"Residential {i}",
                    "URBANopt::Scenario::BaselineMapper"
                ])
        log(f"Wrote mapper CSV to {self.mapper_filename}")
        return self.mapper_filename

    def call_reopt(self, wait=True, use_cached=True, sleep=0, max_threads=5):
        """
        Call reopt for the site's building(s) and write the results.

        :param bool wait: Wait for REopt to return a result before continuing.
        :param float sleep: NUmber of seconds to sleep after each REopt run.
        :return: None if wait=True or a list of thread objects otherwise.
        """
        API_KEY = os.environ.get("NREL_DEV_KEY")
        if not API_KEY:
            raise RuntimeError("NREL_DEV_KEY environment variable missing")

        threads = []

        for building_num in range(1, self.num_simulations + 1):
            # Make a name for the reopt results

            output_path = os.path.join(
                REOPT_RESULTS_PATH, self.scenario_name, str(building_num),
                self.reopt_results_filename(building_num)
                )

            if use_cached and self.reopt_result_exists(building_num):
                continue

            log(f"Running REopt for building {building_num} of "
                  f"{self.num_simulations}")

            payload = self.make_reopt_payload(building_num)
            if wait:
                call_reopt_and_write(payload, API_KEY, output_path)
            else:
                # Make sure we don't go over the maximum thread count.
                while get_num_active_reopt_threads() >= max_threads:
                    print(f"Waiting for other REopt threads to finish "
                         f"({get_num_active_reopt_threads()} running)...")
                    time.sleep(5)
                with thread_lock:
                    thread = threading.Thread(
                        target=call_reopt_and_write,
                        args=(payload, API_KEY, output_path)
                    )
                    thread.start()
                    global REOPT_THREAD_COUNTER
                    REOPT_THREAD_COUNTER += 1
                threads.append(thread)
                if sleep:
                    print(f"Sleeping for {sleep} s after REopt call...")
                    time.sleep(sleep)

        if wait:
            return None
        else:
            return threads

    def reopt_result_exists(self, building_num):
        """
        Return true if the REopt JSON already has been written.
        """
        output_path = os.path.join(
            REOPT_RESULTS_PATH, self.scenario_name, str(building_num),
            self.reopt_results_filename(building_num)
            )
        return os.path.exists(output_path)


    def make_reopt_payload(self, building_num=1):
        """
        Return a dictionary to send to REopt API with the building load.
        """
        template = copy.deepcopy(DEFAULT_REOPT)
        site = template["Scenario"]["Site"]

        for k, v in self.reopt_parameters["Scenario"]["Site"].items():
            site[k].update(v)

        # TODO: Make this configurable somehow...
        template["Scenario"]["time_steps_per_hour"] = self.reopt_timesteps_per_hour
        template["Scenario"]["Site"]["LoadProfile"] = {
            "percent_share": 100,
            "year": 2007,
            "loads_kw": self.get_loads_kw(building_num),
            "loads_kw_is_net": True
        }
        template["Scenario"]["Site"]["latitude"] = self.latitude
        template["Scenario"]["Site"]["longitude"] = self.longitude
        return template

    def get_loads_kw(self, building_num):
        """
        Return a list of the modeled load in kW for the building.
        """
        # Get the name of the feature report folder
        report_folder = [
            f for f in os.listdir(
                os.path.join('run', self.scenario_name, str(building_num)))
            if 'default_feature_reports' in f
        ][0]
        report_csv = os.path.join(
            'run', self.scenario_name, str(building_num),
            report_folder, "default_feature_reports.csv")
        report = pd.read_csv(
            report_csv, index_col=0, infer_datetime_format=True,
            parse_dates=True
        )
        # Check and make sure the timestep matches what we expect.
        report_timestep = (report.index[1] - report.index[0]).total_seconds()
        if not (3600 / self.scenario_timesteps_per_hour == report_timestep):
            raise RuntimeError(
                "Mismatch in simulated timestep vs. scenario timestep, "
                f"building {building_num} of {self.scenario_name}")
        return round(
            report["Electricity:Facility(kWh)"] * self.scenario_timesteps_per_hour, 3
        ).tolist()


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
            building_parameter = getattr(self, key)
            if building_parameter is None or building_parameter == "":
                continue
            output["properties"][key] = building_parameter

        return output

    @property
    def mapper_filename(self):
        return self.scenario_name + ".csv"

    @property
    def scenario_filename(self):
        return self.scenario_name + ".json"

    def reopt_results_filename(self, building_num):
        """
        Unique name based on the REopt parameters and site load.
        """
        reopt_site = self.reopt_parameters["Scenario"]["Site"]

        net_metering = \
            reopt_site["ElectricTariff"]["net_metering_limit_kw"] != 0
        net_metering = "true" if net_metering else "false"

        urdb = reopt_site["ElectricTariff"]["urdb_label"]

        storage_rebate = \
            reopt_site["Storage"]["total_rebate_us_dollars_per_kwh"]

        timesteps = self.reopt_timesteps_per_hour

        # Make a unique `UUID`
        uuid = getID(
            {
                "net metering": net_metering,
                "urdb": urdb,
                "storage_rebate": storage_rebate,
                "timesteps": timesteps,
                "schedule": self.schedules_type
            }
        )

        return f"{urdb}-net-metering-{net_metering}-rebate-" \
               f"{storage_rebate}-{uuid}.json".replace(" ", "-").lower()

    @property
    def scenario_name(self):
        """
        Filename base that is unique based on the building simulation parameters
        (excluding reopt)

        TODO: Handle adding in WFH schedules
        """
        if self.building_parameters.get('schedules_occupant_types'):
            return \
                f'home-{self.location}-{self.number_of_bedrooms}-bd-' \
                f'{self.floor_area}-sched-{self.schedules_type}-occ-' \
                f'{self.building_parameters.get("schedules_occupant_types")}-' \
                f'hvac-setback-{int(self.hvac_thermostat_offset)}-' \
                f'{self.building_sim_uuid}'.replace(' ', '-').lower()
        else:
            return \
                f'home-{self.location}-{self.number_of_bedrooms}-bd-' \
                f'{self.floor_area}-sched-{self.schedules_type}-' \
                f'{self.building_sim_uuid}'.replace(' ', '-').lower()

    @property
    def base_filename(self):
        if not self.tag:
            return \
                f"res-scenario-" \
                f"{self.schedules_type}-schedule-{self.scenario_timesteps_per_hour}-" \
                f"steps-{self.location.lower().replace(' ', '-')}"
        else:
            return self.tag

    @property
    def begin_date(self):
        """
        Beginning date for simulations. Set in 2007 because that's what the
        schedule generator uses for the year...
        """
        begin = datetime.datetime(2007, 1, 1, 0, 0)
        # begin = pytz.timezone(self.timezone).localize(begin)
        # begin = begin.astimezone(pytz.utc)
        return begin.strftime('%Y-%m-%dT%H:00:00.000')
        # return begin.strftime('%Y-%m-%dT%H:00:00.000Z')

    @property
    def end_date(self):
        """
        Ending date for simulations Set in 2007 because that's what the schedule
        generator uses for the year...
        """
        end = datetime.datetime(2007, 12, 31, 23, 59)
        # end = pytz.timezone(self.timezone).localize(end)
        # end = end.astimezone(pytz.utc)
        return end.strftime('%Y-%m-%dT%H:%M:%S.000')
        # return end.strftime('%Y-%m-%dT%H:%M:%S.000Z')

    @property
    def building_sim_uuid(self):
        """
        Return a UUID corresponding to the building simulation parameters
        (exclude all reopt stuff)
        """
        params = {
            "location": self.location,
            "weatherfile": self.weatherfile,
            "climate_zone": self.climate_zone,
            "latitude": self.latitude,
            "longitude": self.longitude,
            "num_simulations": self.num_simulations,
            "timesteps_per_hour": self.scenario_timesteps_per_hour,
        }
        params = {**params, **self.building_parameters}
        # If occupants_type isn't set, don't include it for backcompatibility
        # if 'schedules_occupant_types' in params and \
        #         not params['schedules_occupant_types']:
        #     del params['schedules_occupant_types']
        return getID(params)


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

    def run_building_sim(self, use_cached=True, trace=False):
        """
        Run simulations and post-process the building.

        If use_cached, then will not overwrite old building simulation files.
        """
        clear_baseline = [
            "bundle",
            "exec",
            "rake",
            f"clear_baseline[{self.scenario_filename},{self.mapper_filename}]"
        ]
        run_baseline = [
            "bundle",
            "exec",
            "rake",
            f"run_baseline[{self.scenario_filename},{self.mapper_filename}]"
        ]
        post_process = [
            "bundle",
            "exec",
            "rake",
            f"post_process_baseline[{self.scenario_filename},{self.mapper_filename}]"
        ]
        if trace:
            clear_baseline.append('--trace')
            run_baseline.append('--trace')
            post_process.append('--trace')

        if use_cached and self.results_exist():
            log(
                "Run output already generated, using cache files in "
                f"{self.scenario_name}")
            return
        try:
            log("Clearing old simulation files...")
            clearing = subprocess.check_output(clear_baseline, cwd="../")
            log(clearing.decode('utf-8'))
            log("Old files cleared!")
            log("Starting simulation rake task...")
            running = subprocess.check_output(
                run_baseline, cwd="../"
            )
            log(running.decode('utf-8'))
            log("Finished simulation!")
            # We need to run this to get the power values to send to reopt.
            log("Running URBANopt post-processor")
            post_process = subprocess.check_output(
                post_process, cwd="../"
            )
            log(post_process.decode('utf-8'))
            log("Finished URBANopt post-processing")
        except KeyboardInterrupt as e:
            log("Keyboard interrupted...")
            raise e
        except Exception as e:
            log("Error running task!")
            self.cleanup()
            raise e

    def results_exist(self):
        """
        Return true if the scenario has already been run
        (there is a folder in `run` with the same name and the appropriate
        folders are populated)
        """
        if not (self.scenario_name in os.listdir("./run")):
            return False

        if not ('run_status.json' in
                os.listdir(os.path.join('run', self.scenario_name))):
            return False

        run_status = os.path.join(
            "run", self.scenario_name, "run_status.json")

        with open(run_status, "r") as f:
            results = json.load(f)
        status = results['results']
        # Check that all the runs completed.
        for i in range(self.num_simulations):
            try:
                if status[i]["status"] != "Complete":
                    return False
            except IndexError:
                return False

        return True

    def cleanup(self):
        # Write the simulation parameters into the directory and remove other
        # run files.

        # Move the scenario JSON into the run folder so it's traceable and
        # remove reopt and CSV mapper files.
        subprocess.run(
            [
                "mv", f"{self.scenario_filename}",
                f"run/{self.scenario_name}/urbanopt_scenario.json"
            ]
        )
        subprocess.run(["rm", f"{self.mapper_filename}"], cwd=".")


def get_num_active_reopt_threads():
    with thread_lock:
        return REOPT_THREAD_COUNTER


def getID(mydic):
    """
    Create unique ID to tag JSON.
    """
    ID = 0
    for x in mydic.keys():
        # Hash the content
        ID = ID + int(
            hashlib.sha256(str(mydic[x]).encode('utf-8')).hexdigest(), 16
            )
        # Hash the key
        ID = ID + int(hashlib.sha256(x.encode('utf-8')).hexdigest(), 16)
    return (ID % 10**10)


def call_reopt_and_write(payload, api_key, output_filepath):
    """
    Call REopt and write results.
    """
    try:
        start = time.monotonic()
        root_url = REOPT_URL
        log(f"Making REopt call to {root_url}...")
        post_url = root_url + '/v1/job/?api_key=' + api_key
        results_url = \
            root_url + '/v1/job/<run_uuid>/results/?api_key=' + api_key
        # Turn off verification because the private server certificate is
        # expired...
        verify = root_url == DEFAULT_REOPT_URL
        resp = requests.post(post_url, json=payload, verify=verify)
        if not resp.ok:
            msg = "REopt status code {}. {}".format(resp.status_code,
                                                    resp.content)
            raise RuntimeError(msg)

        run_id_dict = json.loads(resp.text)
        try:
            run_id = run_id_dict['run_uuid']
        except KeyError:
            msg = "Response from {} did not contain run_uuid.".format(post_url)
            raise KeyError(msg)

        results = reopt_poller(url=results_url.replace('<run_uuid>', run_id))

        if results['outputs']['Scenario']['status'] != 'optimal':
            error_msg = results['messages'].get('error')
            if error_msg:
                print(error_msg)
            raise RuntimeError(
                f"Job {run_id} completed with non-optimal status: "
                f"{results['outputs']['Scenario']['status']}")

        # Make directory if not existing
        if not os.path.exists(os.path.dirname(output_filepath)):
            try:
                os.makedirs(os.path.dirname(output_filepath))
            except OSError as exc: # Guard against race condition
                if exc.errno != errno.EEXIST:
                    raise

        with open(output_filepath, "w+") as f:
            json.dump(results, f)
        log(f"Wrote REopt results to {output_filepath}")
        end = time.monotonic()
        print(f"Run {run_id} took {round(end - start)} seconds to finish.")
    except Exception as e:
        print(e)
    finally:
        with thread_lock:
            global REOPT_THREAD_COUNTER
            REOPT_THREAD_COUNTER -= 1



def reopt_poller(url, poll_interval=3):
    """
    Function for polling the REopt API results URL until status is not
    "Optimizing..."

    :param url: results url to poll
    :param poll_interval: seconds
    :return: dictionary response (once status is not "Optimizing...")
    """
    key_error_count = 0
    key_error_threshold = 3
    status = "Optimizing..."

    start = time.monotonic()
    timeout = 500

    while True:
        resp = requests.get(url=url, verify=False)
        try:
            resp_dict = json.loads(resp.content)
        except json.decoder.JSONDecodeError as e:
            print("Error reading REopt response:")
            print(resp.content)
            raise e

        try:
            status = resp_dict['outputs']['Scenario']['status']
        except KeyError:
            key_error_count += 1
            log('REopt KeyError count: {}'.format(key_error_count))
            if key_error_count > key_error_threshold:
                log(
                    "Breaking polling loop due to KeyError count threshold of "
                    "{} exceeded.".format(key_error_threshold))
                break
        if status != "Optimizing...":
            break
        elif (time.monotonic() - start) > timeout:
            raise RuntimeError("Breaking polling loop since timeout exceeded.")
        else:
            time.sleep(poll_interval)

    return resp_dict


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Run our scenarios.')
    parser.add_argument('--run-all', default=False, action='store_true',
                        help=f'run all scenarios in {TEMPLATE_DIRECTORY}')
    parser.add_argument('--pattern', type=str,
                        help='regex pattern to restrict which files are run '
                             'with --run-all')
    parser.add_argument('--file',
                        help=f'run a specified scenario in {TEMPLATE_DIRECTORY}')
    parser.add_argument('--reopt-async', action='store_true',
                        help=f"Don't wait for REopt to finish before continuing.")
    parser.add_argument('--max-reopt-threads', default=5, type=int,
                        help="Maximum number of simultaneous REopt jobs to "
                             "run at any time.")
    parser.add_argument('--ignore-scenario-cache', action='store_true',
                        help=f"Rerun OpenStudio for each scenario.")
    parser.add_argument('--ignore-reopt-cache', action='store_true',
                        help=f"Rerun REopt every time.")
    parser.add_argument('--skip-reopt', action='store_true',
                        help=f"Don't run REopt on the scenarios.")
    parser.add_argument('--trace', action='store_true',
                        help="Trace rake tasks")
    parser.add_argument('--sleep', default=0, type=int,
                        help=
                            "Number of seconds to sleep between REopt calls "
                            "to prevent hitting the REopt API limit. Only "
                            "applies if the --reopt-async"
                            "flag is set.")
    parser.add_argument('--reverse', action='store_true',
                        help=f"Reverse the order which scenarios are run.")
    args = parser.parse_args()

    start = time.monotonic()

    reopt_wait = not args.reopt_async

    if args.file:
        template = os.path.join(TEMPLATE_DIRECTORY, args.file)
        simulation = Simulation.from_json(template)
        simulation.write_mapper_csv()
        simulation.write_scenario_json()
        simulation.run_building_sim(
            not args.ignore_scenario_cache, trace=args.trace)
        # simulation.cleanup()
        end = time.monotonic()
        log(f"Finished building simulation in {round(end - start, 1)} seconds.")
        if not args.skip_reopt:
            simulation.call_reopt(
                wait=reopt_wait, use_cached=not args.ignore_reopt_cache,
                sleep=args.sleep, max_threads=args.max_reopt_threads)
        end = time.monotonic()
    elif args.run_all:
        files = os.listdir(TEMPLATE_DIRECTORY)
        templates = []

        request_threads = []

        for f in files:
            if re.match(r'template-.*-\d+.json', f):
                # Check regex match if we've specified a pattern.
                if args.pattern and not re.match(args.pattern, f):
                    continue
                templates.append(f)
        if len(templates) < 10:
            log(f"Files to run: {templates}")
        # sort the templates so we get the same ordering.
        templates = sorted(templates)
        if args.reverse:
            templates.reverse()
        total = len(templates)
        number_run = 0
        start = time.monotonic()

        for i, template in enumerate(templates):
            loop_start = time.monotonic()
            template = os.path.join(TEMPLATE_DIRECTORY, template)

            log(f"Running template {template}")
            simulation = Simulation.from_json(template)
            simulation.write_mapper_csv()
            simulation.write_scenario_json()
            try:
                simulation.run_building_sim(
                    not args.ignore_scenario_cache, args.trace)
                simulation.cleanup()
            except Exception as e:
                log("ERROR:")
                log(e)
            end = time.monotonic()
            log(
                f"Finished building simulation in {end - loop_start} seconds.")
            try:
                if not args.skip_reopt:
                    reopt_threads = simulation.call_reopt(
                        wait=reopt_wait, sleep=args.sleep,
                        use_cached=not args.ignore_reopt_cache,
                        max_threads=args.max_reopt_threads)
            except Exception as e:
                log("Error running REopt")
                log(e)

            remaining = total - i - 1
            estimated_remaining = (
                (end  - start) / (i + 1) * remaining) / 60
            log(f"Simulation {i+1} of {total} finished.")
            log("Estimated remaining time: "
                  f"{round(estimated_remaining, 1)} min")
            log("Total time elapsed since start: "
                f"{round((time.monotonic() - start) / 60, 1)} min")

    if REOPT_THREAD_COUNTER == 0:
        sys.exit(0)

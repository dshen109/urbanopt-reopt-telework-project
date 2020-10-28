"""
Read the sites.csv, tariffs.csv, and storage.csv files to create all possible
iterations of template JSONs give the options.
"""
import argparse
import csv
import hashlib
import itertools
import json
import os
import pprint

import pandas as pd
from timezonefinder import TimezoneFinder

timezone_finder = TimezoneFinder()

SITES_FILE = "sites.csv"
TARIFFS = "tariffs.csv"
STORAGE = "storage.csv"

# Directory to throw all the JSONs into.
TEMPLATE_DIRECTORY = 'outputs'

os.makedirs(TEMPLATE_DIRECTORY, exist_ok=True)


def csv_load(file_name):
    with open(file_name, 'r') as f:
        return list(list(rec) for rec in csv.reader(f, delimiter=','))


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


def flatten_dict(d):
    def items():
        for key, value in d.items():
            if isinstance(value, dict):
                for subkey, subvalue in flatten_dict(value).items():
                    yield key + "." + subkey, subvalue
            else:
                yield key, value

    return dict(items())



if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate scenario templates")
    parser.add_argument("--location",
                        help="Only generate templates for this location")
    parser.add_argument("--sites", default=SITES_FILE,
                        help="CSV file containing site information.")

    args = parser.parse_args()

    with open("default_building.json", "r") as f:
        DEFAULT_BUILDING = json.load(f)

    sites = csv_load(args.sites)
    tariffs = csv_load(TARIFFS)
    storage = csv_load(STORAGE)
    header = sites.pop(0) + tariffs.pop(0) + storage.pop(0)
    rows = []
    for row in itertools.product(sites, tariffs, storage):
        rows.append(row[0] + row[1] + row[2])

    runs = pd.DataFrame(rows, columns=header)

    # Generate a JSON
    for _, row in runs.iterrows():
        if args.location:
            if row["location"] != args.location:
                continue

        if row['net metering'] == 'true':
            net_metering_limit = 100
        else:
            net_metering_limit = 0

        tariff_name = row['tariff name']
        location = row['location']
        schedules_type = row['schedules_type']
        building = {
            **DEFAULT_BUILDING, **{'schedules_type': schedules_type}
        }
        # Optional add of occupant types so we don't change the UUIDs of the
        # scenarios already generated
        if row['occupant_types']:
            building['schedules_occupant_types'] = row['occupant_types']

        urdb_label = row['urdb']
        kwh_rebate = int(row['kwh_rebate'])
        climate_zone = row['climate_zone']
        weatherfile = row['weatherfile']
        latitude = float(row['latitude'])
        longitude = float(row['longitude'])
        num_simulations = int(row['num_simulations'])
        timesteps_per_hour = int(row['timesteps_per_hour'])
        occupant_types = row['occupant_types']

        template = {
            "location": location,
            'building': building,
            'reopt': {
                'Scenario': {
                    'Site': {
                        'ElectricTariff': {
                            'urdb_label': urdb_label,
                            'net_metering_limit_kw': net_metering_limit
                        },
                        'Storage': {
                            'total_rebate_us_dollars_per_kwh': kwh_rebate
                        },
                    }
                }
            },
            'climate_zone': climate_zone,
            'weatherfile': weatherfile,
            'latitude': latitude,
            'longitude': longitude,
            'num_simulations': num_simulations,
            'timesteps_per_hour': timesteps_per_hour,
            'timezone': timezone_finder.timezone_at(
                lat=latitude, lng=longitude)
        }

        if occupant_types:
            template['occupant_types'] = occupant_types

        # UUID tags the run based on the dictionary contents so don't overwrite
        uuid = getID(flatten_dict(template))
        urdb_beginning = urdb_label[:5]
        tag = \
            f"{location}-{tariff_name}-{urdb_beginning}-net-metering-" \
            f"{row['net metering']}-sched-{schedules_type}-{num_simulations}-" \
            f"sims-rebate-{kwh_rebate}-{uuid}".replace(' ', '-').lower()
        template['tag'] = tag
        fname = 'template-'+ tag + '.json'
        with open(os.path.join(TEMPLATE_DIRECTORY, fname), 'w+') as output:
            print(f"writing {fname}...")
            json.dump(template, output, indent=2)

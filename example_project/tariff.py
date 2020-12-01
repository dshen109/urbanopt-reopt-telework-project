"""
Visualization of utility tariffs
"""
import calendar
import logging
import json

import matplotlib.pyplot as plt
import requests
import seaborn as sns

log = logging.getLogger(__name__)


class Rate(object):

    def __init__(self, rate, util=None):
        """
        :param rate: str, rate name (must include util name) or URDB rate label
        :param util: str, optional
        """
        self.util = util
        self.rate = rate  # rate name string

        self.urdb_dict = self.get_rate() # can return None

    def get_rate(self):
        """
        Logging wrapper.
        """
        rate_dict = self.download_rate()
        if rate_dict is not None:
            log.info('Found rate in URDB.')
        else:
            return None

        return rate_dict

    def download_rate(self):
        """
        Check URDB for rate.
        :return: Either rate dict or None
        """

        url_base = "http://api.openei.org/utility_rates?"
        api_key = "BLLsYv81d8y4w6UPYCfGFsuWlu4IujlZYliDmoq6"
        request_params = {
            "version": "8",
            "format": "json",
            "detail": "full",
            "api_key": api_key,
        }

        using_rate_label = False
        # no spaces in rate label, assume spaces in rate name
        if " " not in self.rate or self.util is None:
            request_params["getpage"] = self.rate
            using_rate_label = True

        else:
            # have to replace '&' to handle url correctly
            request_params["ratesforutility"] = self.util.replace("&", "%26")

        log.info('Checking URDB for {}...'.format(self.rate))
        res = requests.get(url_base, params=request_params, verify=False)

        if not res.ok:
            log.debug('URDB response not OK. Code {} with message: {}'.format(res.status_code, res.text))
            raise Warning('URDB response not OK.')
            # return None

        data = json.loads(res.text, strict=False)
        rates_in_util = data['items']  # data['items'] contains a list of dicts, one dict for each rate in util

        if len(rates_in_util) == 0:
            log.info('Could not find {} in URDB.'.format(self.rate))
            return None

        if not using_rate_label:
            matched_rates = []
            start_dates = []

            for rate in rates_in_util:

                if rate['name'] == self.rate:
                    matched_rates.append(rate)  # urdb can contain multiple rates of same name

                    if 'startdate' in rate:
                        start_dates.append(rate['startdate'])

            # find the newest rate of those that match the self.rate
            newest_index = 0

            if len(start_dates) > 1 and len(start_dates) == len(matched_rates):
                newest_index = start_dates.index(max(start_dates))

            if len(matched_rates) > 0:
                newest_rate = matched_rates[newest_index]
                return newest_rate
            else:
                log.info('Could not find {} in URDB.'.format(self.rate))
                return None

        elif rates_in_util[0]['label'] == self.rate:
            return rates_in_util[0]

        else:
            log.info('Could not find {} in URDB'.format(self.rate))
            return None

    def energy_rate(self, month, hour, weekend, tier=0):
        """
        Return the cost of energy for the given moment.

        Tier numbering starts at 0.
        """
        period = self.get_period(month, hour, weekend, 'energy')
        return self.energyratestructure[period][tier]

    def demand_rate(self, month, hour, weekend, tier=0):
        period = self.get_period(month, hour, weekend, 'demand')
        return self.demandratestructure[period][tier]


    def get_period(self, month, hour, weekend=False, schedule_type='energy'):
        """
        Get the numerical utility period for the given parameters.

        Period numbering starts at 0.

        :param int month: Month, with January = 0
        :param int hour: Hour, with midnight = 0
        :param bool weekend:
        :param str schedule_type: Type of schedule, options are
            `energy` or `demand`
        :rtype: int
        """
        if schedule_type not in ('energy', 'demand'):
            raise ValueError(f"Invalid schedule_type: {schedule_type}")
        if schedule_type == 'demand' and not self.has_demand_charge:
            raise ValueError("This rate does not have a demand change.")

        schedule_query = \
            f"{schedule_type}{'weekend' if weekend else 'weekday'}schedule"
        schedule = getattr(self, schedule_query)
        return schedule[month][hour]

    @property
    def num_periods(self):
        """
        Number of unique energy periods defined by the utility rate
        """
        return len(self.energyratestructure)

    @property
    def has_demand_charge(self):
        try:
            self.demandratestructure
            return True
        except AttributeError:
            return False

    @property
    def has_tiered_energy_charge(self):
        for rate in self.energyratestructure:
            if len(rate) > 1:
                return True
        return False

    @property
    def has_tou(self):
        """
        Return true if the rate has a time of use structure.
        """
        for month in self.energyweekdayschedule:
            if not _all_equal(month):
                return False
        for month in self.energyweekendschedule:
            if not _all_equal(month):
                return False

    @property
    def num_seasons(self):
        """
        Return the number of unique energy schedules by month.
        """
        schedules = set()
        for month in range(12):
            weekday = tuple(self.energyweekdayschedule[month])
            weekend = tuple(self.energyweekendschedule[month])
            schedules.add((weekday, weekend))
        return len(schedules)

    def visualize_energy_rates(self, figsize=(12, 7), palette='flare'):
        """
        Make graph of energy rates.

        :return: matplotlib figure object
        """
        fig, axs = plt.subplots(self.num_seasons, 2, sharex=True, sharey=True,
                                figsize=figsize, squeeze=False)
        month_groups = {}
        for month in range(12):
            weekday = tuple(self.energyweekdayschedule[month])
            weekend = tuple(self.energyweekendschedule[month])
            if (weekday, weekend) in month_groups:
                month_groups[(weekday, weekend)].append(month)
            else:
                month_groups[(weekday, weekend)] = [month]

        period_cmap = self.colorpalette('energy', palette)

        row_count = 0
        for schedule, months in month_groups.items():
            month_names = [calendar.month_abbr[i+1] for i in months]
            weekday_sched, weekend_sched = schedule
            weekday_ax = axs[row_count][0]
            weekend_ax = axs[row_count][1]

            weekday_colors = [period_cmap[period] for period in weekday_sched]
            weekend_colors = [period_cmap[period] for period in weekend_sched]

            hour = list(range(24))

            weekday_ax.bar(
                hour, self.periods_to_prices(weekday_sched), align='edge',
                width=1, color=weekday_colors
            )
            weekday_ax.set_title(
                f"Weekday Energy Rates:\n{', '.join(month_names)}"
            )

            weekend_ax.bar(
                hour, self.periods_to_prices(weekend_sched), align='edge',
                width=1, color=weekend_colors
            )
            weekend_ax.set_title(
                f"Weekend Energy Rates:\n{', '.join(month_names)}"
            )

            weekday_ax.set_ylabel("Price ($ / kWh)")

            # TODO: How to handle tiered rates?
            row_count += 1

        axs[-1][0].set_xlabel("Hour of day")
        axs[-1][1].set_xlabel("Hour of day")

        fig.tight_layout()
        return fig

    def visualize_demand_rates(self, figsize=(12, 7), palette='flare'):
        """
        Make graph of demand rates.

        :return: matplotlib figure object
        """
        if not self.has_demand_charge:
            return None
        fig, axs = plt.subplots(self.num_seasons, 2, sharex=True, sharey=True,
                                figsize=figsize, squeeze=False)
        month_groups = {}
        for month in range(12):
            weekday = tuple(self.demandweekdayschedule[month])
            weekend = tuple(self.demandweekendschedule[month])
            if (weekday, weekend) in month_groups:
                month_groups[(weekday, weekend)].append(month)
            else:
                month_groups[(weekday, weekend)] = [month]

        period_cmap = self.colorpalette('demand', palette)

        row_count = 0
        for schedule, months in month_groups.items():
            month_names = [calendar.month_abbr[i+1] for i in months]
            weekday_sched, weekend_sched = schedule
            weekday_ax = axs[row_count][0]
            weekend_ax = axs[row_count][1]

            weekday_colors = [period_cmap[period] for period in weekday_sched]
            weekend_colors = [period_cmap[period] for period in weekend_sched]

            hour = list(range(24))

            weekday_ax.bar(
                hour, self.periods_to_prices(weekday_sched, which='demand'),
                align='edge', width=1, color=weekday_colors
            )
            weekday_ax.set_title(
                f"Weekday Demand Rates:\n{', '.join(month_names)}"
            )

            weekend_ax.bar(
                hour, self.periods_to_prices(weekend_sched, which='demand'),
                align='edge', width=1, color=weekend_colors
            )
            weekend_ax.set_title(
                f"Weekend Demand Rates:\n{', '.join(month_names)}"
            )

            weekday_ax.set_ylabel("Price ($ / kW)")

            # TODO: How to handle tiered rates?
            row_count += 1

        axs[-1][0].set_xlabel("Hour of day")
        axs[-1][1].set_xlabel("Hour of day")

        fig.tight_layout()
        return fig

    def __getattr__(self, attr):
        """
        Allow getting of URDB parameters using dot notation.
        """
        try:
            return self.urdb_dict[attr]
        except KeyError:
            pass

        return object.__getattribute__(self, attr)

    def periods_to_prices(self, periods, tier=0, which='energy'):
        """
        Convert a list of periods to the energy prices.
        """
        if which == 'energy':
            structure = self.energyratestructure
        elif which == 'demand':
            structure = self.demandratestructure
        else:
            raise ValueError(f"Unknown structure: {which}")
        return [
            structure[period][tier]['rate']
            for period in periods
        ]

    def colorpalette(self, schedule_type='energy', palette='flare'):
        """
        Return a dictionary mapping the periods to colors.

        TODO: Make this more intelligent... like by mapping periods to part
        peak, on-peak, etc.
        """
        colormap = sns.color_palette(palette, as_cmap=True)

        # For each of the periods, assign it a 0 - 1 value for the colormap
        # based on how "close" to noon that period is. e.g. periods on average
        # closer to noon get values closer to 1.
        period_hours = {}
        for period in range(len(self.energyratestructure)):
            period_hours[period] = self._period_hours(period, schedule_type)
            # convert values to distance from noon.
            period_hours[period] = [abs(12 - h) for h in period_hours[period]]

        closeness = {period: sum(hours) / len(hours)
                     for period, hours in period_hours.items()}
        # scale the closenesses to between 0 and 1
        max_closeness = max(closeness.values())
        min_closeness = min(closeness.values())
        if len(period_hours) == 1:
            closeness_scaled = {0: 0}
        else:
            closeness_scaled = {
                period: (c - min_closeness) / (max_closeness - min_closeness)
                for period, c in closeness.items()
            }
        return {period: colormap(c) for period, c in closeness_scaled.items()}

    def _period_hours(self, period, schedule_type='energy'):
        """
        Get a list of all the hours across months and weekends a period applies
        to.
        """
        hours = []
        for week_days in ('weekend', 'weekday'):
            schedule = getattr(self, f"{schedule_type}{week_days}schedule")
            for month in schedule:
                for hour, period_num in enumerate(month):
                    if period == period_num:
                        hours.append(hour)
        return hours


def _all_equal(iterator):
    return len(set(iterator)) <= 1

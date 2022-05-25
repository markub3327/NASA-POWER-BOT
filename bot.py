import argparse
from datetime import datetime, timedelta, timezone

# import seaborn as sns
# import matplotlib.pyplot as plt
import numpy as np
import requests
import yaml

from utils import get_area, is_leap_year, num_of_leap_years_in_range

my_parser = argparse.ArgumentParser(
    prog="python3 download.py",
    description="Download the dataset from NASA Power API",
)
my_parser.add_argument(
    "-start",
    "--year-start",
    type=int,
    help="Year start",
    required=True,
)
my_parser.add_argument(
    "-end",
    "--year-end",
    type=int,
    help="Year end",
    required=True,
)
my_parser.add_argument(
    "-width",
    "--area-width",
    type=float,
    help="Area width",
    required=True,
)
my_parser.add_argument(
    "-height",
    "--area-height",
    type=float,
    help="Area height",
    required=True,
)
my_parser.add_argument(
    "-t",
    "--timeout",
    type=int,
    help="Timeout",
    default=300,  # 5 minutes
)
args = my_parser.parse_args()

# year end
if args.year_end > datetime.utcnow().year:
    print("Error: year end is greater than current year")
    exit(1)

# constants
DAY = 24 * 60 * 60  # hours

with open("locations.yml", "r", encoding="utf8") as file:
    content = yaml.safe_load(file)
    target_locations = content["target_locations"]

DAYS_PER_NON_LEAP_YEAR = 365
DAYS_PER_LEAP_YEAR = 366

leap_years = num_of_leap_years_in_range(start=args.year_start, end=args.year_end)
T = (leap_years * DAYS_PER_LEAP_YEAR) + (
    ((args.year_end - args.year_start + 1) - leap_years) * DAYS_PER_NON_LEAP_YEAR
)

if args.year_end == datetime.utcnow().year:
    T -= (
        datetime(year=args.year_end, month=12, day=31, hour=23, minute=0, second=0)
        - datetime.utcnow()
    ).days
P = len(target_locations)
F = int(
    args.area_width * 2 * args.area_height * 2
)  # NASA POWER resolution is 1/2 deg and 1/2 deg !!!
X_all = np.zeros((T, P, F + 2), dtype=np.float32)
y_hourly_all = np.zeros(((T * 24), P, 1 + 4), dtype=np.float32)
y_daily_all = np.zeros((T, P, 1 + 2), dtype=np.float32)

# Timesteps
t_daily, t_hourly = 0, 0
for year in range(args.year_start, args.year_end + 1):
    if is_leap_year(year):
        DAYS_PER_YEAR = DAYS_PER_LEAP_YEAR
    else:
        DAYS_PER_YEAR = DAYS_PER_NON_LEAP_YEAR

    # full year (366/365 days)
    YEAR = DAYS_PER_YEAR * DAY

    # real num. of days in year
    if year == datetime.utcnow().year:
        DAYS_PER_YEAR -= (
            datetime(year=args.year_end, month=12, day=31, hour=23, minute=0, second=0)
            - datetime.utcnow()
        ).days

    # Patches
    for p, location_key in enumerate(target_locations):
        latitude_min, latitude_max, longitude_min, longitude_max = get_area(
            target_locations[location_key],
            width=args.area_width,
            height=args.area_height,
        )

        print(f"{location_key}")
        print(f"Year: {year}")
        print(f"Days per year: {DAYS_PER_YEAR}")
        print("⛅ 🌞 ⚡")
        print("----------------------------------------------------------")
        print(
            f"Target: {target_locations[location_key][0]}, {target_locations[location_key][1]}"
        )
        print(f"Area: {latitude_min}, {latitude_max}, {longitude_min}, {longitude_max}")
        print("----------------------------------------------------------\n")

        # Region - daily
        response_region = requests.get(
            "https://power.larc.nasa.gov/api/temporal/daily/regional?"
            f"start={year}0101&end={year}1231&"
            f"latitude-min={latitude_min}&latitude-max={latitude_max}&longitude-min={longitude_min}&longitude-max={longitude_max}&"
            "community=re&parameters=ALLSKY_SFC_SW_DWN&time-standard=utc&"
            "format=json&header=true",
            verify=True,
            timeout=args.timeout,
        )
        if response_region.status_code == 200:
            content = response_region.json()

            # Header
            units = content["parameters"]["ALLSKY_SFC_SW_DWN"]["units"]
            name = content["parameters"]["ALLSKY_SFC_SW_DWN"]["longname"]
            fill_value = content["header"][
                "fill_value"
            ]  # represents missing values (measurement error)
            print(f"{name} ({units})")
            print(f"Fill value: {fill_value}", "\n")

            for f in range(F):
                features_region = content["features"][f]["properties"]["parameter"][
                    "ALLSKY_SFC_SW_DWN"
                ]
                for t2, time_key in enumerate(features_region):
                    date = datetime.strptime(time_key, "%Y%m%d")
                    timestamp = date.replace(tzinfo=timezone.utc).timestamp()
                    X_all[t_daily + t2, p, f] = features_region[time_key]  # Irradiance

            date = datetime(year=year, month=1, day=1, hour=0, minute=0, second=0)
            for t2 in range(DAYS_PER_YEAR):
                timestamp = date.replace(tzinfo=timezone.utc).timestamp()
                X_all[t_daily + t2, p, -2] = np.sin(
                    timestamp * (2 * np.pi / YEAR)
                )  # Year sin
                X_all[t_daily + t2, p, -1] = np.cos(
                    timestamp * (2 * np.pi / YEAR)
                )  # Year cos
                date += timedelta(days=1)

        else:
            raise ValueError(
                f"Cannot download region dataset with status code {response_region.status_code} 😟"
            )

        # Point - daily
        response_target = requests.get(
            "https://power.larc.nasa.gov/api/temporal/daily/point?"
            f"start={year}0101&end={year}1231&"
            f"latitude={target_locations[location_key][0]}&longitude={target_locations[location_key][1]}&"
            "community=re&parameters=ALLSKY_SFC_SW_DWN&time-standard=utc&"
            "format=json&header=true",
            verify=True,
            timeout=args.timeout,
        )
        if response_target.status_code == 200:
            content = response_target.json()

            # Header
            units = content["parameters"]["ALLSKY_SFC_SW_DWN"]["units"]
            name = content["parameters"]["ALLSKY_SFC_SW_DWN"]["longname"]
            fill_value = content["header"][
                "fill_value"
            ]  # represents missing values (measurement error)
            print(f"{name} ({units})")
            print(f"Fill value: {fill_value}", "\n")

            features_point = content["properties"]["parameter"]["ALLSKY_SFC_SW_DWN"]
            for t2, time_key in enumerate(features_point):
                date = datetime.strptime(time_key, "%Y%m%d")
                timestamp = date.replace(tzinfo=timezone.utc).timestamp()
                y_daily_all[t_daily + t2, p, 0] = features_point[time_key]
                y_daily_all[t_daily + t2, p, 1] = np.sin(
                    timestamp * (2 * np.pi / YEAR)
                )  # Year sin
                y_daily_all[t_daily + t2, p, 2] = np.cos(
                    timestamp * (2 * np.pi / YEAR)
                )  # Year cos
        else:
            raise ValueError(
                f"Cannot download point dataset with status code {response_target.status_code} 😟\n"
            )

        # Point - hourly
        if year >= 2001:
            response_target = requests.get(
                "https://power.larc.nasa.gov/api/temporal/hourly/point?"
                f"start={year}0101&end={year}1231&"
                f"latitude={target_locations[location_key][0]}&longitude={target_locations[location_key][1]}&"
                "community=re&parameters=ALLSKY_SFC_SW_DWN&time-standard=utc&"
                "format=json&header=true",
                verify=True,
                timeout=args.timeout,
            )
            if response_target.status_code == 200:
                content = response_target.json()

                # Header
                units = content["parameters"]["ALLSKY_SFC_SW_DWN"]["units"]
                name = content["parameters"]["ALLSKY_SFC_SW_DWN"]["longname"]
                fill_value = content["header"][
                    "fill_value"
                ]  # represents missing values (measurement error)
                print(f"{name} (k{units})")
                print(f"Fill value: {fill_value}", "\n")

                features_point = content["properties"]["parameter"]["ALLSKY_SFC_SW_DWN"]
                for t2, time_key in enumerate(features_point):
                    date = datetime.strptime(time_key, "%Y%m%d%H")
                    timestamp = date.replace(tzinfo=timezone.utc).timestamp()
                    if features_point[time_key] != fill_value:
                        y_hourly_all[t_hourly + t2, p, 0] = (
                            features_point[time_key] / 1000
                        )  # Wh/m^2 -> kWh/m^2
                    else:
                        y_hourly_all[t_hourly + t2, p, 0] = fill_value

                    y_hourly_all[t_hourly + t2, p, 1] = np.sin(
                        timestamp * (2 * np.pi / YEAR)
                    )  # Year sin
                    y_hourly_all[t_hourly + t2, p, 2] = np.sin(
                        timestamp * (2 * np.pi / DAY)
                    )  # Day sin
                    y_hourly_all[t_hourly + t2, p, 3] = np.cos(
                        timestamp * (2 * np.pi / YEAR)
                    )  # Year cos
                    y_hourly_all[t_hourly + t2, p, 4] = np.cos(
                        timestamp * (2 * np.pi / DAY)
                    )  # Day cos
            else:
                raise ValueError(
                    f"Cannot download point dataset with status code {response_target.status_code} 😟\n"
                )
        else:
            date = datetime(year=year, month=1, day=1, hour=0, minute=0, second=0)
            for t2 in range(DAYS_PER_YEAR * 24):
                timestamp = date.replace(tzinfo=timezone.utc).timestamp()
                y_hourly_all[t_hourly + t2, p, 0] = fill_value  # Irradiance
                y_hourly_all[t_hourly + t2, p, 1] = np.sin(
                    timestamp * (2 * np.pi / YEAR)
                )  # Year sin
                y_hourly_all[t_hourly + t2, p, 2] = np.sin(
                    timestamp * (2 * np.pi / DAY)
                )  # Day sin
                y_hourly_all[t_hourly + t2, p, 3] = np.cos(
                    timestamp * (2 * np.pi / YEAR)
                )  # Year cos
                y_hourly_all[t_hourly + t2, p, 4] = np.cos(
                    timestamp * (2 * np.pi / DAY)
                )  # Day cos
                date += timedelta(hours=1)
            print(
                f"Year {year} is too early for hourly data. Filled with missing value {fill_value}.\n"
            )

    print("Dataset downloaded 🙂\n")

    t_daily += DAYS_PER_YEAR
    t_hourly += DAYS_PER_YEAR * 24

print(t_daily, " ", t_hourly)

print(f"Inputs shape: {X_all.shape}")
print(f"Target daily shape: {y_daily_all.shape}")
print(f"Target hourly shape: {y_hourly_all.shape}")

# Descriptive Statistics
print(f"Minimum: {np.min(X_all, axis=(0, 1))}")
print(f"Maximum: {np.max(X_all, axis=(0, 1))}")
print(f"Mean: {np.mean(X_all, axis=(0, 1))}")
print(f"Standard deviation: {np.std(X_all, axis=(0, 1))}\n")

# Descriptive Statistics
print(f"Minimum: {np.min(y_daily_all, axis=(0, 1))}")
print(f"Maximum: {np.max(y_daily_all, axis=(0, 1))}")
print(f"Mean: {np.mean(y_daily_all, axis=(0, 1))}")
print(f"Standard deviation: {np.std(y_daily_all, axis=(0, 1))}\n")

# Descriptive Statistics
print(f"Minimum: {np.min(y_hourly_all, axis=(0, 1))}")
print(f"Maximum: {np.max(y_hourly_all, axis=(0, 1))}")
print(f"Mean: {np.mean(y_hourly_all, axis=(0, 1))}")
print(f"Standard deviation: {np.std(y_hourly_all, axis=(0, 1))}\n")

# save dataset
np.savez_compressed(
    "dataset/dataset.npz", X=X_all, y_daily=y_daily_all, y_hourly=y_hourly_all
)

# inputs distribution
# sns.displot(X_all.reshape((-1, X_all.shape[-1])), kde=True)
# plt.title("Region")

# target distribution
# sns.displot(y_daily_all.reshape((-1, y_daily_all.shape[-1])), kde=True)
# plt.title("Point - daily")

# target distribution
# sns.displot(y_hourly_all.reshape((-1, y_hourly_all.shape[-1])), kde=True)
# plt.title("Point - hourly")

# plt.show()

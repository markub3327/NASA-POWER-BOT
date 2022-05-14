import seaborn as sns
import matplotlib.pyplot as plt
import requests
import numpy as np
import argparse
import yaml
from utils import num_of_leap_years_in_range, get_area

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
    default=60,
)
args = my_parser.parse_args()

if num_of_leap_years_in_range(start=args.year_start, end=args.year_end) > 0:
    days_per_year = 366
else:
    days_per_year = 365

with open("locations.yml", "r") as file:
    content = yaml.safe_load(file)
    target_locations = content["target_locations"]

T = days_per_year * (args.year_end - args.year_start + 1)
P = len(target_locations)
F = int(
    args.area_width * 2 * args.area_height * 2
)  # NASA POWER resolution is 1/2 deg and 1/2 deg !!!
X_all = np.zeros((T, P, F), dtype=np.float32)
y_all = np.zeros((T, P, 1), dtype=np.float32)

# Timesteps
t = 0
for year in range(args.year_start, args.year_end + 1):

    # Patches
    for p, key in enumerate(target_locations):
        latitude_min, latitude_max, longitude_min, longitude_max = get_area(
            target_locations[key],
            width=args.area_width,
            height=args.area_height,
        )

        print(f"{key}")
        print(f"Year: {year}")
        print("⛅ 🌞 ⚡")
        print("----------------------------------------------------------")
        print(f"Target: {target_locations[key][0]}, {target_locations[key][1]}")
        print(f"Area: {latitude_min}, {latitude_max}, {longitude_min}, {longitude_max}")
        print("----------------------------------------------------------\n")

        # Region
        response_region = requests.get(
            f"https://power.larc.nasa.gov/api/temporal/daily/regional?start={year}0101&end={year}1231&latitude-min={latitude_min}&latitude-max={latitude_max}&longitude-min={longitude_min}&longitude-max={longitude_max}&community=re&parameters=ALLSKY_SFC_SW_DWN&format=json&header=true&time-standard=utc",
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
                x = list(features_region.values())
                X_all[t : t + len(x), p, f] = x
        else:
            raise ValueError(
                f"Cannot download region dataset with status code {response_region.status_code} 😟"
            )

        # Point
        response_target = requests.get(
            f"https://power.larc.nasa.gov/api/temporal/daily/point?start={year}0101&end={year}1231&latitude={target_locations[key][0]}&longitude={target_locations[key][1]}&community=re&parameters=ALLSKY_SFC_SW_DWN&format=json&header=true&time-standard=utc",
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
            y = list(features_point.values())
            y_all[t : t + len(x), p, 0] = y
        else:
            raise ValueError(
                f"Cannot download point dataset with status code {response_target.status_code} 😟\n"
            )

    print("Dataset downloaded 🙂\n")

    t += days_per_year

print(f"Inputs shape: {X_all.shape}")
print(f"Target shape: {y_all.shape}")

# Descriptive Statistics
print(f"Minimum: {np.min(X_all)}")
print(f"Maximum: {np.max(X_all)}")
print(f"Mean: {np.mean(X_all)}")
print(f"Standard deviation: {np.std(X_all)}\n")

# Descriptive Statistics
print(f"Minimum: {np.min(y_all)}")
print(f"Maximum: {np.max(y_all)}")
print(f"Mean: {np.mean(y_all)}")
print(f"Standard deviation: {np.std(y_all)}\n")

# save dataset
np.save("dataset/X_all", X_all)
np.save("dataset/y_all", y_all)

# inputs distribution
sns.displot(X_all.reshape((-1, X_all.shape[-1])), kde=True)
plt.title("Region")

# target distribution
sns.displot(y_all.reshape((-1, y_all.shape[-1])), kde=True)
plt.title("Point")

plt.show()

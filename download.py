from re import L
import seaborn as sns
import matplotlib.pyplot as plt
import requests
import numpy as np
import multiprocessing
import argparse

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

args = my_parser.parse_args()

target_locations = {
    # Original paper
    "Target 1": (23.25991, 77.41261),
    "Target 2": (22.71961, 75.85771),

    # Solar parks in India
    "Bhadla Solar Park": (27.539669, 71.915253),
    "Pavagada Solar Park": (14.251944, 77.447500),
    "Kurnool Ultra Mega Solar Park": (15.681522, 78.283749),
    "NP Kunta": (14.031944, 78.435833),
    "Rewa Ultra Mega Solar": (24.480278, 81.574444),
    "Charanka Solar Park": (23.900000, 71.200000),
    "Kamuthi Solar Power Project": (9.347568, 78.392162),
    "Ananthapuramu - II": (14.980278, 78.045833),
    "Galiveedu solar park": (14.105833, 78.465833),
    "Mandsaur Solar Farm": (24.088056, 75.799722),
    "Kadapa Ultra Mega Solar Park": (14.916389, 78.291944),
    "Welspun Solar MP project": (24.690700, 75.134700),
    "Karnataka I solar power plant": (15.651944, 75.992500),
    "Bitta Solar Power Plant": (23.262778, 69.024167),
    "Dhirubhai Ambani Solar Park": (26.763056, 72.014167),
    "Mithapur Solar Power Plant": (22.409125, 68.993183),
    "Telangana II Solar Power Plant": (16.152778, 77.765556),
}

def num_of_leap_years(year):
    return (year // 4) - (year // 100) + (year // 400) 
  
# Function to calculate the number 
# of leap years in given range 
def num_of_leap_years_in_range(start, end):
    start -= 1
    return (num_of_leap_years(end) - num_of_leap_years(start))

def get_area(loc, width, height):
    offset_x = width / 2
    offset_y = height / 2
    return (loc[0] - offset_x, loc[0] + offset_x, loc[1] - offset_y, loc[1] + offset_y)

if num_of_leap_years_in_range(start=args.year_start, end=args.year_end) > 0:
    days_per_year = 366
else:
    days_per_year = 365

T = (days_per_year * (args.year_end - args.year_start + 1))
P = len(target_locations)
F = int(args.area_width * 2 * args.area_height * 2)
X_all = np.zeros((T, P, F), dtype=np.float32)
y_all = np.zeros((T, P, 1), dtype=np.float32)

# Timesteps
t = 0
for year in range(args.year_start, args.year_end + 1):

    # Patches
    for p, key in enumerate(target_locations):
        latitude_min, latitude_max, longitude_min, longitude_max = get_area(target_locations[key], width=args.area_width, height=args.area_height)

        print(key)
        print("----------------------------------------------------------")
        print(f"Target: {target_locations[key][0]}, {target_locations[key][1]}")
        print(f"Area: {latitude_min}, {latitude_max}, {longitude_min}, {longitude_max}")
        print("----------------------------------------------------------")
    
        response_region = requests.get(
            f"https://power.larc.nasa.gov/api/temporal/daily/regional?start={year}0101&end={year}1231&latitude-min={latitude_min}&latitude-max={latitude_max}&longitude-min={longitude_min}&longitude-max={longitude_max}&community=re&parameters=ALLSKY_SFC_SW_DWN&format=json&header=true&time-standard=utc",
            verify=True,
            timeout=30.00,
        )

        # Region
        if response_region.status_code == 200:
            #print(req.headers)
            content = response_region.json()

            # Header
            units = content["parameters"]["ALLSKY_SFC_SW_DWN"]["units"]
            name = content["parameters"]["ALLSKY_SFC_SW_DWN"]["longname"]
            fill_value = content["header"]["fill_value"]   # represents missing values (measurement error)

            for f in range(F):
                features_region = content["features"][f]["properties"]["parameter"]["ALLSKY_SFC_SW_DWN"]
                x = list(features_region.values())
                X_all[t:t+len(x), p, f] = x
        else:
            raise ValueError(f"Cannot download dataset with status code {response_region.status_code} 😟")

        response_target = requests.get(
            f"https://power.larc.nasa.gov/api/temporal/daily/point?start={year}0101&end={year}1231&latitude={target_locations[key][0]}&longitude={target_locations[key][1]}&community=re&parameters=ALLSKY_SFC_SW_DWN&format=json&header=true&time-standard=utc",
            verify=True,
            timeout=30.00,
        )

        # Point
        if response_target.status_code == 200:
            #print(req.headers)
            content = response_target.json()

            # Header
            units = content["parameters"]["ALLSKY_SFC_SW_DWN"]["units"]
            name = content["parameters"]["ALLSKY_SFC_SW_DWN"]["longname"]
            fill_value = content["header"]["fill_value"]   # represents missing values (measurement error)

            features_point = content["properties"]["parameter"]["ALLSKY_SFC_SW_DWN"]
            y = list(features_point.values())
            y_all[t:t+len(x), p, 0] = x
        else:
            raise ValueError(f"Cannot download dataset with status code {response_target.status_code} 😟\n")

    print(f"Dataset downloaded 🙂\n")

    print(t)
    print(year)

    t += days_per_year

print(X_all.shape)
print(y_all.shape)

# replace bad values with fill value -1 !!!
X_all[X_all < 0] = -1

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

print(np.where(y_all == 0))

# inputs distribution
sns.displot(X_all.reshape((-1, X_all.shape[-1])), kde=True)
plt.title("Region")

# target distribution
sns.displot(y_all.reshape((-1, y_all.shape[-1])), kde=True)
plt.title("Point")
   
plt.show()

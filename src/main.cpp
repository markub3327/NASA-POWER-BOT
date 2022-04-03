#include <iostream>
#include <fstream>
#include "downloader.hpp"
#include "nlohmann/json.hpp"

using std::cout;
using nlohmann::json;

// Function to calculate the number
// of leap years in range of (1, year)
int calNum(int year)
{
    return (year / 4) - (year / 100) +
                        (year / 400);
}

// Function to calculate the number
// of leap years in given range
int leapNum(int start, int end)
{
    start--;
    int num1 = calNum(end);
    int num2 = calNum(start);
	return (num1 - num2);
}

float* get_area(float latitude, float longitude, float width, float height) {
    auto offset_x = width / 2;
    auto offset_y = height / 2;
    
	return new float[] {
        latitude - offset_x,
        latitude + offset_x,
    	longitude - offset_y,
        longitude + offset_y,
	};
}

int main(int argv, char** argc)
{
	// read a JSON file
	std::ifstream i("locations.json");
	json j;
	i >> j;
	auto target_locations = j["target_locations"];

	auto year_start = std::atoi(argc[1]);
	auto year_end = std::atoi(argc[2]);

	auto area_width = std::atof(argc[3]);
	auto area_height = std::atof(argc[4]);

	auto days_per_year = leapNum(year_start, year_end) > 0 ? 366 : 365;
	auto T = days_per_year * (year_end - year_start + 1);
	auto P = target_locations.size();
	auto F = (unsigned int) (area_width * 2 * area_height * 2);
    // NASA POWER resolution is 1/2 deg and 1/2 deg !!!
	float X_all[T][P][F];
	float y_all[T][P][1];

	std::cout << "T: " << T << std::endl;
	std::cout << "P: " << P << std::endl;
	std::cout << "F: " << F << std::endl;

	// Timesteps
	for (int year = year_start, t = 0; year < std::atoi(argc[2]) + 1; year++, t += days_per_year)
	{
		// Patches
		int p = 0, t2;
		for (json::iterator it = target_locations.begin(); it != target_locations.end(); ++it, ++p) {
			auto region_area = get_area(it.value()[0], it.value()[1], area_width, area_height);

			std::cout << it.key() << std::endl;
			std::cout << "Year: " << year << std::endl;

			std::cout << "⛅ 🌞 ⚡" << std::endl;
			std::cout << "----------------------------------------------------------" << std::endl;
			std::cout << "Region: " << region_area[0] << "\t" << region_area[1] << "\t" << region_area[2] << "\t" << region_area[3] << std::endl;
			std::cout << "Target: " << it.value()[0] << ", " << it.value()[1] << std::endl;
			//print(f"Area: {latitude_min}, {latitude_max}, {longitude_min}, {longitude_max}")
			std::cout << "----------------------------------------------------------\n" << std::endl;
	
			auto d_region = new Downloader(
				("https://power.larc.nasa.gov/api/temporal/daily/regional?start="+std::to_string(year)+"0101&end="+std::to_string(year)+"1231&latitude-min="+std::to_string(region_area[0])+"&latitude-max="+std::to_string(region_area[1])+"&longitude-min="+std::to_string(region_area[2])+"&longitude-max="+std::to_string(region_area[3])+"&community=re&parameters=ALLSKY_SFC_SW_DWN&format=json&header=true&time-standard=utc")
			);
			auto d_target = new Downloader(
				("https://power.larc.nasa.gov/api/temporal/daily/point?start="+std::to_string(year)+"0101&end="+std::to_string(year)+"1231&latitude="+std::to_string((float)(it.value()[0]))+"&longitude="+std::to_string((float)(it.value()[1]))+"&community=re&parameters=ALLSKY_SFC_SW_DWN&format=json&header=true&time-standard=utc")
			);

			// Region
			auto response_region = d_region->download();
			for (int f = 0; f < F; f++)
			{
                auto features_region = response_region["features"][f]["properties"]["parameter"]["ALLSKY_SFC_SW_DWN"];
				t2 = 0;
				for (json::iterator it2 = features_region.begin(); it2 != features_region.end(); ++it2, ++t2) {
	                X_all[t + t2][p][f] = it2.value();
				}
				std::cout << t+t2 << ", " << p << ", " << f << std::endl;
			}

			// Target
			auto response_target = d_target->download();
			auto features_point = response_target["properties"]["parameter"]["ALLSKY_SFC_SW_DWN"];
			t2 = 0;
			for (json::iterator it2 = features_point.begin(); it2 != features_point.end(); ++it2, ++t2) {
				y_all[t + t2][p][0] = it2.value();
			}
			std::cout << t+t2 << ", " << p << std::endl;

			delete d_region;
			delete d_target;
		}
	}

	std::cout << "Dataset downloaded 🙂\n";

	return 0;
}
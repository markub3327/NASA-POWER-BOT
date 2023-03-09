# NASA POWER Bot

[NASA POWER](https://power.larc.nasa.gov/)

  Bot for downloading Solar irradiance data at target locations and region surrounded it.

  It use [NASA POWER API](https://power.larc.nasa.gov/docs/services/api/) to get data.

# Setup
To initialize, run the setup.jl file using the following command:

  ```bash
    julia setup.jl 
  ```

# Example Usage

1. After the setup, Go to config/ and modify the data in the files to match your requirements.

2. Run the following command to download the data:

  ```
  julia --threads 8 main.jl --start 2010 --end 2015 --width 5 --height 5
  ```
The above command will download all available data from the given locations betwwen 1st January 2010 and 31st December 2015, using 8 threads.
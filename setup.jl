using Pkg

# Install Required Packages
Pkg.add(["Dates", "DataFrames", "CSV", "YAML", "ProgressMeter", "HTTP", "JSON", "ArgParse", "GLMakie", "Statistics", "StatsBase", "EnergyStatistics"])

# Create dataset folder if it doesn't exist already
if !isdir("dataset")
    mkdir("dataset")
end


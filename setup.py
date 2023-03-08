import os
os.system("julia install_packages.jl")
if not os.path.exists('dataset'):
    os.mkdir('dataset')
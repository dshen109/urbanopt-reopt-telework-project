# OpenStudio-HPXML

[![CircleCI](https://circleci.com/gh/NREL/OpenStudio-HPXML.svg?style=shield)](https://circleci.com/gh/NREL/OpenStudio-HPXML)
[![Documentation Status](https://readthedocs.org/projects/openstudio-hpxml/badge/?version=latest)](https://openstudio-hpxml.readthedocs.io/en/latest/?badge=latest)
[![codecov](https://codecov.io/gh/NREL/OpenStudio-HPXML/branch/master/graph/badge.svg)](https://codecov.io/gh/NREL/OpenStudio-HPXML)

OpenStudio-HPXML allows running residential EnergyPlus simulations using an [HPXML file](https://hpxml.nrel.gov/) for the building description.
A Schematron document (`HPXMLtoOpenStudio/resources/EPvalidator.xml`) for the EnergyPlus use case is used to validate that the appropriate HPXML inputs are provided to run EnergyPlus.

OpenStudio-HPXML can accommodate a wide range of different building technologies and geometries.
End-to-end simulations typically run in 3-10 seconds, depending on complexity, computer platform and speed, etc.

For more information on running simulations, generating HPXML files, etc., please visit the [documentation](https://openstudio-hpxml.readthedocs.io/en/latest).

## Workflows

A simple [run_simulation.rb script](https://github.com/NREL/OpenStudio-HPXML/blob/master/workflow/run_simulation.rb) is provided to run a residential EnergyPlus simulation from an HPXML file.
See the [Getting Started](https://openstudio-hpxml.readthedocs.io/en/latest/getting_started.html#getting-started) section of the documentation for running simulations.

Since [OpenStudio measures](http://nrel.github.io/OpenStudio-user-documentation/getting_started/about_measures/) are used for model generation, additional OpenStudio-based workflows and interfaces can be used instead if desired.

## Measures

This repository contains two OpenStudio measures:
- `HPXMLtoOpenStudio`: A measure that translates an HPXML file to an OpenStudio model.
- `SimulationOutputReport`: A reporting measure that generates a variety of annual/timeseries CSV outputs for a residential HPXML-based model.

## Projects

The OpenStudio-HPXML workflow is used by a number of other residential projects, including:
- [Energy Rating Index (ERI)](https://github.com/NREL/OpenStudio-ERI)
- Home Energy Score (private repository)
- Weatherization Assistant (private repository)
- ResStock (pending)
- UrbanOpt (pending)

## License

This project is available under a BSD-3-like license, which is a free, open-source, and permissive license. For more information, check out the [license file](https://github.com/NREL/OpenStudio-HPXML/blob/master/LICENSE.md).

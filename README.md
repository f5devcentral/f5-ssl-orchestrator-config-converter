<div align="center">

# F5 SSL ORCHESTRATOR CONFIG CONVERTER


[Documentation](https://clouddocs.f5networks.net/ssl-orchestrator-config-converter/1.0/cm_sslo_how_to_migrate_configuration.html)

[![docker pulls](https://img.shields.io/docker/pulls/f5devcentral/f5-ssl-orchestrator-config-converter.svg)](https://hub.docker.com/r/f5devcentral/f5-ssl-orchestrator-config-converter)
[![image size](https://img.shields.io/docker/image-size/f5devcentral/f5-ssl-orchestrator-config-converter?sort=semver)](https://hub.docker.com/r/f5devcentral/f5-ssl-orchestrator-config-converter)
[![version](https://img.shields.io/docker/v/f5devcentral/f5-ssl-orchestrator-config-converter?sort=semver)](https://hub.docker.com/r/f5devcentral/f5-ssl-orchestrator-config-converter)
[![github issues](https://img.shields.io/github/issues-raw/f5devcentral/f5-ssl-orchestrator-config-converter)](https://github.com/f5devcentral/f5-ssl-orchestrator-config-converter/issues)
[![license](https://img.shields.io/badge/license-Apache--2.0-green)](https://github.com/f5devcentral/f5-ssl-orchestrator-config-converter/blob/main/LICENSE)

</div>

## Introduction

F5 SSL Orchestrator config converter is an early access, self-contained application, designed for the purpose of transitioning/converting SSL Orchestrator configurations from the BIG-IP platform to the next-generation BIG-IP environment. This application is distributed as a Docker image, allowing users to create the converted configuration on BIG-IP Next Central Manager.

Refer to product documentation for more details.

## Quick Start

To convert SSL Orchestrator configuration from BIG-IP to CM SSL Orchestrator compliant JSON format.

SETUP:
```
Install docker on your local working system (like VM)
```

Command to run F5 SSL Orchestrator config converter docker image
```
$ docker pull f5devcentral/f5-ssl-orchestrator-config-converter:[TAG]      // Pull Docker image from f5devcentral. Use most latest tag.
$ docker run --rm -v "$PWD":/usr/app/data <image_name:[TAG]>               // Run docker container.

```

Details about docker run command:
```
Working directory in docker container /usr/app

$ docker run -it --rm -v "$PWD":/usr/app/data <image_name:[TAG]> -i <data/input_ifile> -o <data/output.json>
|--rm |                 Automatically remove the container when it exits.                                         |
|-v   |--volume list    Bind mount a volume, Mount a volume from local to docker container.                       |
|-i   | input ifile       <path> Specify path to input ifile.                                                       |
|-o   | output file     <path> Specify output file for the converted json results. (default "data/output.json")   |
|–log | logfile         <file> outputs log to the specified file. (default "os.Stdout")                           |

NOTE: Due to the least privilege of user 'f5docker' as the default user in docker container, you need to create the output file first and make sure it can be written by other users including f5docker. Additionally, this also applies to logfile, if user provides -log flag.

touch output.json
chmod a+rw output.json

touch logfile.txt
chmod a+rw logfile.txt

```

## Support

If you come across a bug please [submit an issue](https://github.com/f5devcentral/f5-automation-config-converter/issues) to our team.

# service-clone.sh
A shell script to copy service settings to another service.

# Usage

## Setup

### Prerequisites

This script requires at least `curl` and `jq` commands to be available on your machine.

### API Token

Please set `FASTLY_API_TOKEN` environment variable with your API token.

```sh
export FASTLY_API_TOKEN="your_api_token"
```

```sh
$ chmod +x ./service-clone.sh
```

## Help

```text
$ ./service-clone.sh -h
Usage: ./service-clone.sh [OPTIONS]

List of available options
  -s, --src SERVICE_ID    [required] source service ID
  -d, --dst SERVICE_ID    [required] destinatuon service ID
  -v, --version VERSION   (optional) source version number (default: the current active version)
  --no-logging            (optional) exclude logging settings (default: include)
  --no-acl                (optional) exclude acl (default: include)
  --no-dictionary         (optional) exclude dictionry (default: include)
  -h, --help              show help

Need more help? Visit: https://github.com/smaeda-ks/fastly-service-clone
```

## Command

```sh
$ ./service-clone.sh -s ${source_service_id} -d ${destination_service_id}
```

# service-clone.sh
A shell script to copy service settings to another service.

# Usage

### Setup

Open `service-clone.sh` file and replace `your_api_token` with your API token.

```sh
readonly API_TOKEN='your_api_token'
```

```
$ chmod +x ./service-clone.sh
```

### Help

```text
$ ./service-clone.sh -h
Usage: ./service-clone.sh [OPTIONS]

List of available options
  -s, --src SERVICE_ID    [required] source service ID
  -d, --dst SERVICE_ID    [required] destinatuon service ID
  -v, --version VERSION   (optional) source version numver (default: the current active version)
  --no-logging            (optional) exclude logging settings (default: include)
  --no-acl                (optional) exclude acl (default: include)
  --no-dictionary         (optional) exclude dictionry (default: include)
  -h, --help              show help

Need more help? Visit: https://github.com/smaeda-ks/fastly-service-clone
```

### Command

```text
$ ./service-clone.sh -s ${source_service_id} -d ${destination_service_id}
```

#!/usr/bin/env bash
# Production health panel: one line per configured ECS service with a state
# colour, the key numbers, and the service name as an OSC 8 link into the AWS
# console. Meant for a terminal pane next to pr-panel.sh.
#
# Source of truth is AWS CloudWatch in the configured production account and
# region, read directly with the AWS CLI. Read-only calls, three per process
# start and two per refresh:
#   aws sts get-caller-identity          once, to prove the profile lands in production
#   aws cloudwatch get-metric-data       one batch: ECS/ContainerInsights task counts,
#                                        ALB 5xx / requests / p99 per target group,
#                                        Application Signals where a service has it
#   aws cloudwatch describe-alarms       all alarms; ALARM and INSUFFICIENT_DATA are
#                                        matched to services and summarised
#
# Credentials: a named AWS CLI profile (SSO) via AWS_PROFILE or
# PROD_HEALTH_AWS_PROFILE. No keys, no files. Needs cloudwatch:GetMetricData and
# cloudwatch:DescribeAlarms in the production account, nothing else.
#
# Settings come from ~/.config/firstmate/panels.conf (see panels.conf.example):
#   PROD_HEALTH_ACCOUNT_ID, PROD_HEALTH_REGION, PROD_HEALTH_AWS_PROFILE,
#   PROD_HEALTH_SERVICES (JSON list of services, format below).
#
# Usage: prod-health-panel.sh [refresh-seconds] [--once]
set -u
# Local settings (organisation, accounts, services) live outside this repo.
panels_config=${FIRSTMATE_PANELS_CONFIG:-$HOME/.config/firstmate/panels.conf}
# shellcheck source=/dev/null
[ -r "$panels_config" ] && . "$panels_config"
interval=60
once=0
for arg in "$@"; do
  case $arg in
    --once) once=1 ;;
    *) interval=$arg ;;
  esac
done

region=${PROD_HEALTH_REGION:-eu-central-1}
account=${PROD_HEALTH_ACCOUNT_ID:-}
profile=${PROD_HEALTH_AWS_PROFILE:-${AWS_PROFILE:-}}
console="https://$region.console.aws.amazon.com"
alarms_url="$console/cloudwatch/home?region=$region#alarmsV2:"
export AWS_PAGER=""
red=$'\033[31m' yel=$'\033[33m' dim=$'\033[2m' rst=$'\033[0m'

# PROD_HEALTH_SERVICES is a JSON list, one object per service:
#   key         short id (letters, digits, -)
#   label       text shown in the panel
#   cluster     ECS cluster name   } ECS/ContainerInsights dimensions
#   service     ECS service name   }
#   tg          ALB target-group name, or null when the service has no ALB
#   match_re    regex matched against alarm names, metric names and dimension values
#   dash        CloudWatch dashboard name to link instead of the ECS service page, or null
#   appsignals  true when CloudWatch Application Signals covers the service
services=${PROD_HEALTH_SERVICES:-[]}

work=$(mktemp -d "${TMPDIR:-/tmp}/prod-health.XXXXXX") || exit 1
chmod 700 "$work"
body_file=$work/body
err_file=$work/err
payload_file=$work/payload.json
metrics_file=$work/metrics.json
alarms_file=$work/alarms.json
rows_file=$work/rows
for f in "$metrics_file" "$alarms_file"; do printf 'null\n' >"$f"; done
: >"$rows_file"
identity_ok=0
identity_role=""
identity_account=""
last_ok=""
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT TERM

link() { printf '\033]8;;%s\033\\%s\033]8;;\033\\' "$1" "$2"; }

# UTC timestamp N minutes ago, ISO 8601, for --start-time/--end-time.
utc_ago() {
  date -u -v-"$1"M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "$1 minutes ago" +%Y-%m-%dT%H:%M:%SZ
}

# aws_call <aws args...> -> stdout in $body_file. Returns 0 on success; on failure
# sets err_kind (profile|sso|nocreds|denied|network|other) and err_msg.
aws_call() {
  err_kind=""
  err_msg=""
  if aws --profile "$profile" --region "$region" --output json --no-cli-pager \
       --cli-connect-timeout 10 --cli-read-timeout 25 "$@" >"$body_file" 2>"$err_file"; then
    return 0
  fi
  err_msg=$(tr -d '\n' <"$err_file" | sed -e 's/^An error occurred //' | head -c 110)
  local lower
  lower=$(printf '%s' "$err_msg" | tr '[:upper:]' '[:lower:]')
  case $lower in
    *"could not be found"*) err_kind=profile ;;
    *"sso"*"expired"*|*"token has expired"*|*"error loading sso token"*|*"sso login"*|*"expiredtoken"*|*"invalidgranttype"*) err_kind=sso ;;
    *"unable to locate credentials"*|*"nocredentialproviders"*) err_kind=nocreds ;;
    *"accessdenied"*|*"not authorized"*|*"unauthorizedoperation"*) err_kind=denied ;;
    *"could not connect"*|*"endpointconnectionerror"*|*"connect timeout"*|*"read timeout"*|*"name resolution"*|*"nodename nor servname"*) err_kind=network ;;
    *) err_kind=other ;;
  esac
  return 1
}

# One line explaining an aws_call failure, coloured unless called with "plain".
explain_error() {
  local r=$red y=$yel z=$rst
  [ "${1:-}" = plain ] && r="" && y="" && z=""
  case $err_kind in
    profile) printf '%sAWS profile %s not found%s  run: aws configure sso  (account %s, read-only permission set)' "$r" "$profile" "$z" "$account" ;;
    sso) printf '%sAWS SSO session expired%s  run: aws sso login --profile %s' "$y" "$z" "$profile" ;;
    nocreds) printf '%sno AWS credentials for profile %s%s  run: aws sso login --profile %s' "$r" "$profile" "$z" "$profile" ;;
    denied) printf '%saccess denied%s  profile %s needs cloudwatch:GetMetricData + cloudwatch:DescribeAlarms in %s' "$r" "$z" "$profile" "$account" ;;
    network) printf '%sCloudWatch unreachable%s  %s' "$r" "$z" "$err_msg" ;;
    *) printf '%sAWS error%s  %s' "$r" "$z" "$err_msg" ;;
  esac
}

build_payload() {
  # $q carries the single quote so the jq program itself stays free of them.
  jq -n --argjson svc "$services" --arg q "'" '
    def stat($id; $ns; $m; $dims; $s): {
      Id: $id, ReturnData: true,
      MetricStat: { Metric: { Namespace: $ns, MetricName: $m,
                              Dimensions: [ $dims | to_entries[] | {Name: .key, Value: .value} ] },
                    Period: 60, Stat: $s } };
    def dyn($d): "${PROP(" + $q + "Dim." + $d + $q + ")}";
    def search($id; $schema; $filter; $m; $s; $label): {
      Id: $id, ReturnData: true, Label: $label,
      Expression: ("SEARCH(" + $q + "{" + $schema + "} " + $filter + "MetricName=\"" + $m + "\"" + $q
                   + ", " + $q + $s + $q + ", 60)") };
    [ $svc[] | (.key | gsub("-"; "_")) as $k
      | stat("run_" + $k; "ECS/ContainerInsights"; "RunningTaskCount"; {ClusterName: .cluster, ServiceName: .service}; "Average"),
        stat("des_" + $k; "ECS/ContainerInsights"; "DesiredTaskCount"; {ClusterName: .cluster, ServiceName: .service}; "Average") ]
    + [ search("alb5xx"; "AWS/ApplicationELB,LoadBalancer,TargetGroup"; ""; "HTTPCode_Target_5XX_Count"; "Sum"; dyn("TargetGroup")),
        search("albreq"; "AWS/ApplicationELB,LoadBalancer,TargetGroup"; ""; "RequestCount"; "Sum"; dyn("TargetGroup")),
        search("albp99"; "AWS/ApplicationELB,LoadBalancer,TargetGroup"; ""; "TargetResponseTime"; "p99"; dyn("TargetGroup")) ]
    + [ $svc[] | select(.appsignals) | (.key | gsub("-"; "_")) as $k | ("Service=\"" + .service + "\" ") as $f
      | search("aslat_" + $k; "ApplicationSignals,Environment,Service"; $f; "Latency"; "p99"; dyn("Environment")),
        search("asfault_" + $k; "ApplicationSignals,Environment,Service"; $f; "Fault"; "Sum"; dyn("Environment")),
        search("asreq_" + $k; "ApplicationSignals,Environment,Service"; $f; "Latency"; "SampleCount"; dyn("Environment")) ]'
}

# Turns the metric and alarm responses into one TSV row per service:
# key, label, state, detail, url
compute_rows() {
  jq -r -n --argjson svc "$services" --arg console "$console" --arg region "$region" \
    --slurpfile mm "$metrics_file" --slurpfile aa "$alarms_file" '
    $mm[0] as $m | $aa[0] as $a |
    def nonnull: [ .[]? | select(. != null) ];
    def results($id): [ ($m.MetricDataResults // [])[] | select(.Id == $id) ];
    # --scan-by TimestampDescending puts the newest value first.
    def latest($id): [ results($id)[] | .Values[]? ] | nonnull | .[0];
    def total($id): [ results($id)[] | .Values[]? ] | nonnull | if length == 0 then null else add end;
    def tg_results($id; $tg): [ results($id)[] | select((.Label // "") | test("targetgroup/" + $tg + "/")) ];
    def tg_total($id; $tg): [ tg_results($id; $tg)[] | .Values[]? ] | nonnull | if length == 0 then null else add end;
    def tg_latest($id; $tg): [ tg_results($id; $tg)[] | (.Values | nonnull | .[0]) ] | nonnull | if length == 0 then null else max end;
    def failed($id): [ results($id)[] | select(.StatusCode == "InternalError" or ((.Messages // []) | length) > 0)
                         | ((.Messages // [{Value: .StatusCode}])[0].Value) ] | .[0];
    def alarms: (($a.MetricAlarms // []) + ($a.CompositeAlarms // []));
    def alarm_text: (.AlarmName // "") + " " + (.Namespace // "") + " " + (.MetricName // "") + " "
                    + ([ .Dimensions[]?.Value ] | join(" ")) + " "
                    + ([ .Metrics[]?.MetricStat?.Metric?.Dimensions[]?.Value ] | join(" "));
    def matched($re): [ alarms[] | select(alarm_text | test($re; "i")) ];
    def pct($x; $n): if ($n // 0) > 0 then (100 * ($x // 0) / $n) else null end;
    def fmt1: if . == null then "-" else ((. * 10 | round) / 10 | tostring) end;
    def fmt0: if . == null then "-" else (round | tostring) end;

    $svc[] as $sv
    | ($sv.key | gsub("-"; "_")) as $k
    | (failed("run_" + $k) // failed("des_" + $k)) as $err
    | latest("run_" + $k) as $run
    | latest("des_" + $k) as $des
    | (if $sv.tg then tg_total("alb5xx"; $sv.tg) else null end) as $e5
    | (if $sv.tg then tg_total("albreq"; $sv.tg) else null end) as $req
    | (if $sv.tg then tg_latest("albp99"; $sv.tg) else null end) as $p99
    | (if $sv.appsignals then latest("aslat_" + $k) else null end) as $aslat
    | (if $sv.appsignals then total("asfault_" + $k) else null end) as $asfault
    | (if $sv.appsignals then total("asreq_" + $k) else null end) as $asreq
    | pct($e5; $req) as $e5pct
    | pct($asfault; $asreq) as $faultpct
    | matched($sv.match_re) as $ma
    | ([ $ma[] | select(.StateValue == "ALARM") ] | length) as $alarm
    | ([ $ma[] | select(.StateValue == "INSUFFICIENT_DATA") ] | length) as $insuff
    | (if $m == null then "NOCREDS"
       elif $err != null then "ERR"
       elif $run == null and $des == null then "NODATA"
       elif $run == 0 then "DOWN"
       elif $alarm > 0 then "ALERT"
       elif $des != null and $run < $des then "DEGRADED"
       elif $e5pct != null and $e5pct >= 2 and ($req // 0) >= 20 then "DEGRADED"
       elif $faultpct != null and $faultpct >= 2 and ($asreq // 0) >= 20 then "DEGRADED"
       else "OK" end) as $state
    | (if $state == "NOCREDS" then ""
       elif $state == "ERR" then ($err | tostring | .[0:60])
       elif $state == "NODATA" then "no data"
       else
         ( ($run | fmt0) + "/" + ($des | fmt0) + " tasks" )
         + (if $sv.appsignals and $asreq != null then "  fault " + ($faultpct | fmt1) + "%  p99 " + ($aslat | fmt0) + "ms"
            elif $sv.tg == null then "  no ALB"
            elif $req == null then "  no ALB data"
            else "  5xx " + ($e5pct | fmt1) + "%  p99 " + (if $p99 == null then "-" else (($p99 * 1000) | fmt0) + "ms" end) end)
         + (if $alarm > 0 then "  " + ($alarm | tostring) + " ALARM" else "" end)
         + (if $insuff > 0 then "  " + ($insuff | tostring) + " insufficient" else "" end)
       end) as $detail
    | (if $sv.dash then $console + "/cloudwatch/home?region=" + $region + "#dashboards/dashboard/" + $sv.dash
       else $console + "/ecs/v2/clusters/" + $sv.cluster + "/services/" + $sv.service + "/health?region=" + $region end) as $url
    | [ $sv.key, $sv.label, $state, $detail, $url ] | @tsv'
}

badge() {
  case $1 in
    OK) printf '\033[32m●\033[0m' ;;
    DEGRADED|ERR) printf '\033[33m●\033[0m' ;;
    DOWN|ALERT) printf '\033[31m●\033[0m' ;;
    *) printf '\033[2m○\033[0m' ;;
  esac
}

draw() {
  local status=$1 note=${2:-}
  printf '\033[H\033[2J\033[3J'
  printf '\033[1mProduction health\033[0m  \033[2m%s  CloudWatch %s\033[0m\n' "$(date +%H:%M:%S)" "$region"
  [ -z "$status" ] || printf '%s\n' "$status"
  [ -z "$note" ] || printf '%s%s%s\n' "$dim" "$note" "$rst"
  printf '\n'
  local key label state detail url
  while IFS=$'\t' read -r key label state detail url; do
    [ -n "$key" ] || continue
    printf ' %s ' "$(badge "$state")"
    link "$url" "$(printf '%-30s' "$label")"
    case $state in
      DOWN|ALERT) printf ' \033[31m%s\033[0m' "$detail" ;;
      DEGRADED|ERR) printf ' \033[33m%s\033[0m' "$detail" ;;
      *) printf ' \033[2m%s\033[0m' "$detail" ;;
    esac
    printf '\n'
  done <"$rows_file"
}

# Rows without live data, so the service links still work.
draw_offline() {
  printf 'null\n' >"$metrics_file"
  compute_rows >"$rows_file" 2>/dev/null
  if [ -n "$last_ok" ] && [ -s "$rows_file.last" ]; then
    cp "$rows_file.last" "$rows_file"
    draw "$1" "showing last good data from $last_ok"
  else
    draw "$1" "${2:-links open the ECS service pages}"
  fi
}

# Confirms once per process that the profile lands in the production account.
check_identity() {
  [ "$identity_ok" = 1 ] && return 0
  aws_call sts get-caller-identity || return 1
  identity_account=$(jq -r '.Account // ""' "$body_file" 2>/dev/null)
  identity_role=$(jq -r '.Arn // "" | capture("assumed-role/(?<r>[^/]+)").r // (.Arn // "")' "$body_file" 2>/dev/null)
  if [ "$identity_account" != "$account" ]; then
    err_kind=account
    return 1
  fi
  identity_ok=1
}

render() {
  local status="" note=""
  if ! command -v aws >/dev/null 2>&1; then
    draw_offline "${red}AWS CLI not installed${rst}  brew install awscli"
    return
  fi
  if [ -z "$account" ] || [ "$(printf '%s' "$services" | jq 'length' 2>/dev/null || echo 0)" = 0 ]; then
    draw "${yel}not configured${rst}  set PROD_HEALTH_ACCOUNT_ID and PROD_HEALTH_SERVICES in $panels_config"
    return
  fi
  if [ -z "$profile" ]; then
    draw_offline "${yel}no AWS profile${rst}  set AWS_PROFILE to a production read-only SSO profile (account $account)"
    return
  fi
  if ! check_identity; then
    if [ "$err_kind" = account ]; then
      draw_offline "${red}profile $profile is in account ${identity_account:-?}, not production $account${rst}  refusing to show another account's data"
    else
      draw_offline "$(explain_error)"
    fi
    return
  fi

  build_payload >"$payload_file"
  if ! aws_call cloudwatch get-metric-data --metric-data-queries "file://$payload_file" \
         --start-time "$(utc_ago 10)" --end-time "$(utc_ago 0)" --scan-by TimestampDescending; then
    [ "$err_kind" = sso ] || [ "$err_kind" = nocreds ] && identity_ok=0
    draw_offline "$(explain_error)"
    return
  fi
  cp "$body_file" "$metrics_file"
  last_ok=$(date +%H:%M)

  if aws_call cloudwatch describe-alarms --alarm-types MetricAlarm CompositeAlarm; then
    # Target-tracking auto-scaling alarms (TargetTracking-*, e.g. AlarmLow scale-in
    # signals) sit in ALARM as normal operation, so they are not health alerts.
    local scaling
    scaling=$(jq -r '[(.MetricAlarms // [])[] | select((.AlarmName // "") | startswith("TargetTracking-"))] | length' "$body_file" 2>/dev/null || echo 0)
    jq '.MetricAlarms = [(.MetricAlarms // [])[] | select((.AlarmName // "") | startswith("TargetTracking-") | not)]' "$body_file" >"$alarms_file" 2>/dev/null || cp "$body_file" "$alarms_file"
    local total in_alarm insuff
    total=$(jq -r '(.MetricAlarms // []) + (.CompositeAlarms // []) | length' "$alarms_file" 2>/dev/null || echo 0)
    in_alarm=$(jq -r '[(.MetricAlarms // []) + (.CompositeAlarms // []) | .[] | select(.StateValue == "ALARM")] | length' "$alarms_file" 2>/dev/null || echo 0)
    insuff=$(jq -r '[(.MetricAlarms // []) + (.CompositeAlarms // []) | .[] | select(.StateValue == "INSUFFICIENT_DATA")] | length' "$alarms_file" 2>/dev/null || echo 0)
    if [ "$total" = 0 ]; then
      note="$(link "$alarms_url" alarms): none defined in $account"
    else
      note="$(link "$alarms_url" alarms): $total total, $in_alarm ALARM, $insuff insufficient data (${scaling} auto-scaling alarms ignored)"
    fi
  else
    printf 'null\n' >"$alarms_file"
    note="alarms unavailable: $(explain_error plain)"
  fi
  note="$note  · $profile${identity_role:+ ($identity_role)}"

  if ! compute_rows >"$rows_file.new" 2>"$err_file"; then
    status="${yel}could not parse CloudWatch response${rst}  $(head -c 80 "$err_file" | tr -d '\n')"
    rm -f "$rows_file.new"
  else
    mv "$rows_file.new" "$rows_file"
    cp "$rows_file" "$rows_file.last"
  fi
  draw "$status" "$note"
}

while :; do
  render
  [ "$once" = 1 ] && exit 0
  # Pressing r (or Enter) in the focused pane, or resizing it, refreshes now.
  resized=0; key=""
  trap 'resized=1' WINCH
  read -rsn1 -t "$interval" key </dev/tty 2>/dev/null || true
  trap - WINCH
  [ -n "$key" ] && printf '\033[H\033[2m↻ refreshing…\033[0m\033[K'
done

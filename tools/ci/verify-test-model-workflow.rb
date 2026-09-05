#!/usr/bin/env ruby

require "shellwords"
require "yaml"

MODEL_URL = "https://raw.githubusercontent.com/boto/botocore/" \
  "36c34f15391da01cd717c73c0fffa747c9889768/" \
  "botocore/data/s3/2006-03-01/service-2.json"
MODEL_PATH = "obj/ci/service-2.json"
MODEL_EXPORT = "${{ github.workspace }}/#{MODEL_PATH}"
TEST_JOB_CONTROLS = {
  "name" => "Root and SQLite tests (${{ matrix.os }})",
  "needs" => "integrity",
  "runs-on" => "${{ matrix.os }}",
  "timeout-minutes" => 75,
  "strategy" => {
    "fail-fast" => false,
    "matrix" => {"os" => ["ubuntu-latest", "macos-latest"]}
  }
}.freeze
TEST_STEPS = [
  {
    "name" => "Check out sources",
    "timeout-minutes" => 5,
    "uses" => "actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd",
    "with" => {"fetch-depth" => 0, "persist-credentials" => false}
  },
  {
    "name" => "Install uv",
    "uses" => "astral-sh/setup-uv@c771a70e6277c0a99b617c7a806ffedaca235ff9",
    "with" => {"version" => "0.11.28"}
  },
  {
    "name" => "Fetch pinned botocore S3 model",
    "timeout-minutes" => 5,
    "run" => <<~'SHELL'
      mkdir -p obj/ci
      curl --fail --silent --show-error --location \
        --retry 3 --connect-timeout 15 --max-time 120 \
        https://raw.githubusercontent.com/boto/botocore/36c34f15391da01cd717c73c0fffa747c9889768/botocore/data/s3/2006-03-01/service-2.json \
        --output obj/ci/service-2.json
    SHELL
  },
  {
    "name" => "Install Alire",
    "timeout-minutes" => 15,
    "uses" => "alire-project/setup-alire@fc4c8ce471aa30b3af0d39ce15add1ee9eaf28f2",
    "with" => {
      "version" => "2.1.1",
      "toolchain" => "gnat_native=16.1.0 gprbuild=26.0.1",
      "cache" => true
    }
  },
  {
    "name" => "Configure Flyology index",
    "timeout-minutes" => 5,
    "run" => <<~'SHELL'
      alr index --reset-community
      alr index \
        --add=git+https://github.com/flyology-ada/alire-index.git \
        --name=flyology \
        --before=community
    SHELL
  },
  {
    "name" => "Verify exact indexed HTTP dependency",
    "timeout-minutes" => 5,
    "run" => <<~'SHELL'
      mkdir -p obj/ci
      alr show flyology_http=0.1.3-dev --solve \
        2>&1 | tee obj/ci/http-resolution.log
      grep -Fq 'Origin: commit eb09a80a7e06274e93289861c2cae1ca7e8cb1af' \
        obj/ci/http-resolution.log
      alr show flyology_quic=0.1.3-dev --solve \
        2>&1 | tee obj/ci/quic-resolution.log
      grep -Fq 'Origin: commit eb09a80a7e06274e93289861c2cae1ca7e8cb1af' \
        obj/ci/quic-resolution.log
    SHELL
  },
  {
    "name" => "Run root and SQLite gates",
    "env" => {"FLYOLOGY_S3_SERVICE_MODEL" => MODEL_EXPORT},
    "run" => "./tools/ci/run-tests.sh"
  },
  {
    "name" => "Upload test logs",
    "if" => "${{ always() }}",
    "timeout-minutes" => 5,
    "uses" => "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02",
    "with" => {
      "name" => "tests-${{ matrix.os }}",
      "path" => "obj/ci/*.log",
      "if-no-files-found" => "warn",
      "retention-days" => 14
    }
  }
].freeze

def reject(message)
  warn "workflow policy: #{message}"
  exit 1
end

def mapping(value, description)
  reject("#{description} must be a mapping") unless value.is_a?(Hash)
  value
end

def one_named_step(steps, name)
  matches = steps.each_index.select do |index|
    step = steps[index]
    step.is_a?(Hash) && step["name"] == name
  end
  reject("test job must contain exactly one #{name} step") unless matches.length == 1
  [matches.first, steps[matches.first]]
end

workflow_path = ARGV.fetch(0) do
  reject("workflow file path is required")
end

begin
  workflow = YAML.safe_load(
    File.read(workflow_path, encoding: "UTF-8"),
    permitted_classes: [],
    aliases: false
  )
rescue Errno::ENOENT, Psych::Exception => error
  reject("workflow YAML is invalid: #{error.message}")
end

workflow = mapping(workflow, "workflow")
reject("workflow run defaults are forbidden") if workflow.key?("defaults")
reject("workflow environment is forbidden") if workflow.key?("env")
jobs = mapping(workflow["jobs"], "workflow jobs")
test_job = mapping(jobs["test"], "test job")
reject("test job must be unconditional") if test_job.key?("if")
if test_job.key?("continue-on-error")
  reject("test job must fail the workflow on error")
end
reject("test job run defaults are forbidden") if test_job.key?("defaults")
reject("test job environment is forbidden") if test_job.key?("env")
steps = test_job["steps"]
reject("test job steps must be a sequence") unless steps.is_a?(Array)

fetch_index, fetch_step = one_named_step(
  steps,
  "Fetch pinned botocore S3 model"
)
gate_index, gate_step = one_named_step(steps, "Run root and SQLite gates")

reject("test model fetch step must be unconditional") if fetch_step.key?("if")
reject("root and SQLite gate step must be unconditional") if gate_step.key?("if")
reject("test model fetch environment is forbidden") if fetch_step.key?("env")
if fetch_step.key?("continue-on-error") || gate_step.key?("continue-on-error")
  reject("test model fetch and root/SQLite gate must fail the job on error")
end
if fetch_step.key?("shell") || gate_step.key?("shell")
  reject("test model fetch and root/SQLite gate must use the runner shell")
end
if fetch_step.key?("working-directory") || gate_step.key?("working-directory")
  reject("test model fetch and root/SQLite gate must run from the repository root")
end
if fetch_index >= gate_index
  reject("test job must fetch the pinned model before root and SQLite gates")
end

fetch_run = fetch_step["run"]
reject("test model fetch run must be a string") unless fetch_run.is_a?(String)
logical_lines = fetch_run.gsub(/\\\r?\n/, " ").lines.map(&:strip).reject(&:empty?)
begin
  commands = logical_lines.map { |line| Shellwords.shellsplit(line) }
rescue ArgumentError => error
  reject("test model fetch shell is invalid: #{error.message}")
end
expected_commands = [
  ["mkdir", "-p", "obj/ci"],
  [
    "curl", "--fail", "--silent", "--show-error", "--location",
    "--retry", "3", "--connect-timeout", "15", "--max-time", "120",
    MODEL_URL, "--output", MODEL_PATH
  ]
]
unless commands == expected_commands
  reject("test model fetch must execute the exact pinned download command")
end

gate_env = mapping(gate_step["env"], "root and SQLite gate environment")
unless gate_env.keys == ["FLYOLOGY_S3_SERVICE_MODEL"]
  reject("root and SQLite gate environment must contain only the model path")
end
unless gate_env["FLYOLOGY_S3_SERVICE_MODEL"] == MODEL_EXPORT
  reject("root and SQLite gate must export the exact pinned model path")
end
unless gate_step["run"].is_a?(String) &&
       gate_step["run"].strip == "./tools/ci/run-tests.sh"
  reject("root and SQLite gate must execute the maintained test wrapper")
end

job_controls = test_job.reject { |key, _value| key == "steps" }
unless job_controls == TEST_JOB_CONTROLS
  reject("test job controls must match the reviewed definition")
end
unless steps == TEST_STEPS
  reject("test job steps must match the reviewed sequence and definitions")
end

require "spec"
require "specreporter-spec"
require "../src/crystime"

Spec.override_default_formatter(
 Spec::SpecReporterFormatter.new(
  #indent_string: "    ",        # Indent string. Default "  "
  #width: ENV["COLUMNS"].to_i-2, # Terminal width. Default 78
  # ^-- You may need to run "eval `resize`" in term to get COLUMNS variable
  #elapsed_width: 8,     # Number of decimals for "elapsed" time. Default 3
  #status_width: 10,     # Width of the status field. Default 5
  skip_errors_report: false,  # Skip the default, unwieldy backtraces. Default true
  #skip_slowest_report: false, # Skip the default "slowest" report. Default true
  skip_failed_report: false,  # Skip the default failed reports summary. Default true
))

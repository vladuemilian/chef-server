require 'omnibus-ctl'

class OmnibusCtlHelper
  def initialize(files)
    @ctl = Omnibus::Ctl.new("test-ctl")
    files.each do |file|
      @ctl.load_file(file)
    end
  end

  def run_test_omnibus_command(command, args)
    #$0 = "./bin/omnibus-ctl"
    # we must mock out ARGV.
    # The first three arguments to ARGV in omnibus-ctl are
    # irrelevant to the command, but get passed in anyway.
    ARGV.clear
    ARGV << "stub1"
    ARGV << "stub2"
    ARGV << "stub3"
    args.each do |arg|
      ARGV << arg
    end
    @ctl.run([command])
  end
end

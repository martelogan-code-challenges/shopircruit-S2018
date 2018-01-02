defmodule Commandline.CLI do
  def main(args) do
    {opts,_,_} = OptionParser.parse(args, switches: [challenge_id: :string], aliases: [c: :challenge_id])
    Shopircruit.menus(opts[:challenge_id]) 
  end
end
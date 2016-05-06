#!/usr/bin/env julia
# Tim Sterne-Weiler 2016

const ver = "v0.1-rc1"

tic()
println( STDERR, "Whippet $ver loading and compiling... " )

using ArgParse
using Glob

dir = splitdir(@__FILE__)[1]

push!( LOAD_PATH, dir * "/../src" )
import SpliceGraphs
using SpliceGraphs

function parse_cmd()
  s = ArgParseSettings()
  # TODO finish options...
  @add_arg_table s begin
    "--a", "-a"
      help     = "Replicates for Set A -- Could be: pattern to glob (*common-filename-segment*), or comma delimited list of filenames"
      arg_type = ASCIIString
      required = true
    "--b", "-b"
      help     = "Replicates for Set B -- Could be: pattern to glob (*common-filename-segment*), or comma delimited list of filenames"
      arg_type = ASCIIString
      required = true
    "--out","-o"
      help     = "Core file name to send .diff.gz output to!"
      arg_type = ASCIIString
      default  = fixpath( "$(dir)/../output" )
    "--directory","-d"
      help     = "Directory to search for file patterns or list in -a and -b"
      arg_type = ASCIIString
      default  = "."
    "--min-reads","-r"
      help     = "Minimum number of reads for a single event to be included!"
      arg_type = Int64
      default  = 5
    "--min-samples","-s"
      help     = "Minimum number of samples in a or in b for each event to be considered!"
      arg_type = Int64
      default  = 1
    "--min-delta-psi"
      help     = "Calculate probability of deltaPsi greater than this value."
      arg_type = Float64
      default  = 0.0
  end
  return parse_args(s)
end

function retrievefilelist( pattern::ASCIIString, dir::ASCIIString )
   list = Vector{ASCIIString}()
   if search(pattern, ',') > 0
      tmp = split( pattern, ',' )
   else
      tmp = glob( pattern, dir )
   end
   # now clean the return
   for file in tmp
      push!( list, string(file) )
   end
   list
end

function main()
   args  = parse_cmd()
   dir   = fixpath( args["directory"] )
   lista = retrievefilelist( args["a"], dir )
   listb = retrievefilelist( args["b"], dir )
   if length(lista) <= 0 || length(listb) <= 0
      error("Unable to match files! length(a) == $(length(lista)), length(b) == $(length(listb))!")
   end
   
   astreams = open_streams( lista )
   bstreams = open_streams( listb )   

   process_psi_files( args["out"], astreams, bstreams, 
                      min_samp=args["min-samples"], 
                      min_reads=args["min-reads"],
                      amt=args["min-delta-psi"] ) 
end

main()

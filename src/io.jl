
#=function Base.time_print(elapsedtime, bytes, gctime, allocs)
    @printf(STDERR, "%10.6f seconds", elapsedtime/1e9)
    if bytes != 0 || allocs != 0
        bytes, mb = Base.prettyprint_getunits(bytes, length(_mem_units), Int64(1024))
        allocs, ma = Base.prettyprint_getunits(allocs, length(_cnt_units), Int64(1000))
        if ma == 1
            @printf(STDERR, " (%d%s allocation%s: ", allocs, _cnt_units[ma], allocs==1 ? "" : "s")
        else
            @printf(STDERR, " (%.2f%s allocations: ", allocs, _cnt_units[ma])
        end
        if mb == 1
            @printf(STDERR, "%d %s%s", bytes, _mem_units[mb], bytes==1 ? "" : "s")
        else
            @printf(STDERR, "%.3f %s", bytes, _mem_units[mb])
        end
        if gctime > 0
            @printf(STDERR, ", %.2f%% gc time", 100*gctime/elapsedtime)
        end
        print(")")
    elseif gctime > 0
        @printf(STDERR, ", %.2f%% gc time", 100*gctime/elapsedtime)
    end
    println(STDERR)
end=#

tab_write{S <: AbstractString}( io::BufOut, str::S ) = (write( io, str ); write( io, '\t'  ))
tab_write( io::BufOut, str::Char ) = (write( io, str ); write( io, '\t'  ))

function coord_write( io::BufOut, chr, first, last; tab=false )
   write( io, chr   )
   write( io, ':'   )
   write( io, string(first) )
   write( io, '-'   )
   write( io, string(last)  )
   tab && write( io, '\t' )
end

function coord_write( io::BufOut, chr, first, last, strand; tab=false )
   coord_write( io, chr, first, last )
   write( io, ':'    )
   write( io, strand )
   tab && write( io, '\t' )
end

function seq_write( io::BufOut, read::SeqRecord; tab=false )
   for c in read.seq
      write( io, convert(Char, c) )
   end
   tab && write( io, '\t' )
end

function qual_write( io::BufOut, read::SeqRecord, qualoffset=64; tab=false )
   for i in read.metadata.quality
      write( io, convert(Char, i+qualoffset) )
   end
   tab && write( io, '\t' )
end

function sam_flag( align::SGAlignment, lib::GraphLib, ind )
   flag = UInt16(0)
   lib.info[ ind ].strand || (flag |= 0x10)
   flag   
end

function cigar_string( align::SGAlignment, sg::SpliceGraph )
   matchleft = align.matches
   cigar = ""
   curpos = align.offset
   leftover = 0
   for idx in 1:length( align.path )
      const i = align.path[idx].node
      i <= length(sg.nodeoffset) || return cigar
      if matchleft + curpos <= sg.nodeoffset[i] + sg.nodelen[i] - 1
         cigar *= string( matchleft + leftover ) * "M"
         matchleft = 0
         leftover = 0
      else
         curspace = (sg.nodeoffset[i] + sg.nodelen[i] - 1) - curpos
         matchleft -= curspace
         if idx < length( align.path )
            nexti = align.path[idx+1].node
            nexti <= length(sg.nodeoffset) || return cigar
            curpos = sg.nodeoffset[ nexti ]
            const intron = sg.nodecoord[nexti] - (sg.nodecoord[i] + sg.nodelen[i] - 1)
            if intron > 0
               cigar *= string( curspace ) * "M" * string( intron ) * "N"
            else
               leftover += curspace
            end
         end
      end
   end
   if leftover > 0 || matchleft > 0
      cigar *= string( matchleft + leftover ) * "M"
   end
   cigar
end

function write_sam( io::BufOut, read::SeqRecord, align::SGAlignment, lib::GraphLib; mapq=0 )
   const geneind = align.path[1].gene
   const nodeind = align.path[1].node
   const sg = lib.graphs[geneind] 
   tab_write( io, read.name )
   tab_write( io, string( sam_flag(align, lib, geneind) ) )
   tab_write( io, lib.info[geneind].name )
   tab_write( io, string( sg.nodecoord[nodeind] + (align.offset - sg.nodeoffset[nodeind]) ) )
   tab_write( io, string(mapq) )
   tab_write( io, cigar_string( align, sg ) )
   tab_write( io, '*' )
   tab_write( io, '0' )
   tab_write( io, '0' )
   seq_write( io, read, tab=true )
   qual_write( io, read )
   write( io, '\n' )
end

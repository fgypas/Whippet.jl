const Mb = 1_000_000
const GENOMESIZE = 3235Mb

# ALIAS NEW TYPES FOR INCREASED CODE READABILITY
if GENOMESIZE < typemax(UInt32)
   typealias CoordInt UInt32
else
   typealias CoordInt UInt64
end

if VERSION < v"0.5.0-dev"
   typealias String ASCIIString
end

typealias CoordTuple Tuple{Vararg{CoordInt}}
typealias CoordArray Vector{CoordInt}
typealias ExonMax    UInt16
typealias GeneName   String
typealias SeqName    String
typealias GeneMeta   Tuple{GeneName, SeqName, Char}

typealias Refseqid   String
typealias Txinfo     Tuple{GeneName,CoordInt,CoordInt,CoordInt}
                       #   {GeneName, TxStart, TxEnd, ExonCount}
typealias GeneTup    Tuple{String, Char}
                       #    Chrom/seqname, Strand '+'/'-'
typealias CoordTree IntervalTree{CoordInt,Interval{CoordInt}}

typealias BufOut BufferedStreams.BufferedOutputStream

immutable GeneInfo
   name::SeqName
   strand::Bool # pos is true, neg is false
end

immutable TxInfo
   name::GeneName
   
end

GeneInfo( name::SeqName, strand::Char ) = GeneInfo( name, strand == '+' ? true : false )

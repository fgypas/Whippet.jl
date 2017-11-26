
abstract type ReadCounter end
abstract type BiasModel end

#This may introduce type-instability
#Though it may be necessary...
#Base.get( num::Float64 ) = num 

function pushto!(t::IntervalTrees.IntervalBTree{K, V, B}, key::I, value) where {K, V, B, I <: AbstractInterval{K}}
    return _push!(t.root, key, value)
end

function _push!(t::IntervalTrees.InternalNode{K, V, B}, key::AbstractInterval{K}, value) where {K, V, B}
    i = IntervalTrees.findidx(t, key)
    if 1 <= length(t) - 1 && key >= t.keys[i]
        return _push!(t.children[i+1], key, value)
    else
        return _push!(t.children[i], key, value)
    end
end

function _push!(t::IntervalTrees.LeafNode{K, V, B}, key::AbstractInterval{K}, value) where {K, V, B}
    i = IntervalTrees.findidx(t, key)
    if 1 <= i <= length(t) &&
        first(t.entries[i]) == first(key) && last(t.entries[i]) == last(key)
        push!( t.entries[i].value, value )
        return true
    end
    return false
end

function pushzero!( collection::Dict{K,V}, key, value ) where {K, V <: ReadCounter}
   if !haskey( collection, key )
      collection[key] = zero(ReadCount)
   end
   push!( collection[key], value )
end

function pushzero!( collection::IntervalMap{K,V}, key, value ) where {K <: Integer, V <: ReadCounter}
   if !haskey( collection, (key.first,key.last) )
      collection[key] = zero(ReadCount)
   end
   pushto!( collection, key, value )
end

function Base.get( cnt::R ) where R <: ReadCounter
   if !cnt.isadjusted
      error("Cannot get() read count from model thats not already adjusted!")
   else
      return cnt.count
   end
end

function Base.push!( cnt::R, value::F ) where {R <: ReadCounter, F <: AbstractFloat}
   if cnt.isadjusted
      cnt.count += value
   else
      cnt.count += value
      cnt.isadjusted = true
      #error("Cannot push! a float value to PrimerBiasCounter unless isadjusted is true!")
   end
   cnt
end

Base.identity( cnt::R ) where R <: ReadCounter = get( cnt )
Base.identity( cnt::IntervalValue{I,R} ) where R <: ReadCounter = get( cnt.value )

struct DefaultBiasMod <: BiasModel end

mutable struct DefaultCounter <: ReadCounter
   count::Float64
   isadjusted::Bool

   DefaultCounter() = new( 1.0, true )
   DefaultCounter( i::Float64 ) = new( i, true )
end

const DEFAULTCOUNTER_ZERO = DefaultCounter(0.0)
const DEFAULTCOUNTER_ONE  = DefaultCounter(1.0)

Base.zero( ::Type{DefaultCounter} ) = DefaultCounter(0.0) #DEFAULTCOUNTER_ZERO
Base.one( ::Type{DefaultCounter} )  = DefaultCounter(1.0) #DEFAULTCOUNTER_ONE
Base.push!( cnt::DefaultCounter, value::Float64 ) = (cnt.count += value)

adjust!( cnt::DefaultCounter, m::B ) where B <: BiasModel = (cnt.isadjusted = true)
count!( mod::DefaultBiasMod, anything ) = 1.0

# 5' Sequence bias model
# Implementation of Hansen et al, NAR 2010 

struct PrimerBiasMod <: BiasModel
   fore::Vector{Float64}
   back::Vector{Float64}
   size::Int64
   backoffset::Int64
   backnpos::Int64
   foreoffset::Int64
   forenpos::Int64

   temp::Vector{UInt16}

   function PrimerBiasMod( ksize::Int=6, backoff::Int=24, backn::Int=6, foreoff::Int=2, foren::Int=3 )
      fore = zeros( 4^ksize )
      back = zeros( 4^ksize )
      temp = zeros(UInt16, foren)
      new( fore, back, ksize, backoff, backn, foreoff, foren, temp )
   end
end

Base.normalize!( mod::PrimerBiasMod, lib, quant ) = normalize!( mod )

function Base.normalize!( mod::PrimerBiasMod )
   foresum = sum(mod.fore)
   backsum = sum(mod.back)
   @inbounds for i in 1:length(mod.fore)
      @fastmath mod.fore[i] = mod.fore[i] / foresum
      @fastmath mod.back[i] = mod.back[i] / backsum
   end
end

function count!( mod::PrimerBiasMod, seq::BioSequence{A} ) where A <: BioSequences.Alphabet
   idx = 1
   for i in mod.foreoffset:(mod.foreoffset+mod.forenpos-1)
      hept = kmer_index_trailing(UInt16, seq[i:(i+mod.size-1)])
      mod.fore[hept+1] += 1.0
      mod.temp[idx] = hept
      idx += 1
   end
   for i in mod.backoffset:(mod.backoffset+mod.backnpos-1)
      mod.back[kmer_index_trailing(UInt16, seq[i:(i+mod.size-1)])+1] += 1.0
   end
   return mod.temp
end

@fastmath value!( mod::PrimerBiasMod, hept::UInt16 ) = mod.back[hept+1] / mod.fore[hept+1]

# hash by identity for speed
Base.hash( v::UInt16 ) = v

mutable struct PrimerBiasCounter <: ReadCounter
   count::Float64
   map::Dict{UInt16,Int32}
   isadjusted::Bool

   PrimerBiasCounter() = new( 0.0, Dict{UInt16,Int32}(), false )
end

Base.zero(::Type{PrimerBiasCounter}) = PrimerBiasCounter()

@inline function adjust!( cnt::PrimerBiasCounter, mod::PrimerBiasMod )
   for (k,v) in cnt.map
      cnt.count += value!( mod, k ) * v
   end
   cnt.count /= mod.forenpos
   cnt.isadjusted = true
end

function Base.push!( cnt::PrimerBiasCounter, vhept::Vector{UInt16} )
   for j in 1:length(vhept)
      push!( cnt, vhept[j] )
   end
end

function Base.push!( cnt::PrimerBiasCounter, hept::UInt16 )
   if haskey( cnt.map, hept )
      cnt.map[hept] += 1
   else
      cnt.map[hept] = 1
   end
   cnt
end

# GC-Content Bias Correction


struct GCBiasMod <: BiasModel
   fore::Vector{Float64}
   back::Vector{Float64}
   gcsize::Int64
   gcwidth::Float64
   gcoffset::Int64
   gcincrement::Int64

   temp::Vector{Int16}

   function GCBiasMod( gcoffset::Int=5, gcincrement::Int=25; gc_param = GCBiasParams(50, 0.05) )
      fore = zeros(Float64, Int(ceil(1.0 / gc_param.width)+1))
      back = zeros(Float64, Int(ceil(1.0 / gc_param.width)+1))
      temp = zeros(Int16, 11)
      new( fore, back, gc_param.length, gc_param.width, gcoffset, gcincrement, temp ) 
   end
end

function add_to_back!( back::Vector{Float64}, exp::ExpectedGC, weight::Float64 )
   for i in 1:length(exp)
      back[i] += exp[i] * weight
   end
   mod
end

mutable struct GCBiasCounter <: ReadCounter
   count::Float64
   gc::Vector{Int16}
   isadjusted::Bool

   function GCBiasCounter( gc_param = GCBiasParams(50, 0.05) )
      gc = zeros(Int16, Int(ceil(1.0 / gc_param.width)+1))
      new(0.0, gc, true)
   end
end

Base.zero(::Type{GCBiasCounter}) = GCBiasCounter()

value!( mod::GCBiasMod, bin::Int ) = mod.fore[bin] > 0.0 ? mod.back[bin] / mod.fore[bin] : 1.0

function count!( mod::GCBiasMod, seq::BioSequence{A} ) where A <: BioSequences.Alphabet
   fill!(mod.temp, zero(Int16))
   idx = 1
   for i in mod.gcoffset:mod.gcincrement:(length(seq)-mod.gcsize)
      gc = gc_content(seq[i:(i+mod.gcsize-1)])
      bin = Int(div( gc, mod.gcwidth )+1)
      mod.fore[bin] += 1.0
      mod.temp[idx] = bin
      idx += 1
   end
   mod.temp
end

function adjust!( cnt::GCBiasCounter, mod::GCBiasMod )
   #cnt.count = sum(cnt.gc) # TODO FOR OMNI
   weight    = 0.0
   for i in 1:length(cnt.gc)
      weight += value!( mod, i ) * cnt.gc[i]
   end
   if sum(cnt.gc) > 0
      weight /= sum(cnt.gc)
      cnt.count *= weight
   end
   cnt.isadjusted = true
   cnt
end

function Base.push!( cnt::GCBiasCounter, bins::Vector{Int16} )
   cnt.count += 1 # TODO FOR OMNI
   for i in 1:length(bins)
      if bins[i] > 0
         push!( cnt, bins[i] )
      else
         return cnt
      end
   end
   cnt
end

function Base.push!( cnt::GCBiasCounter, bin::Int16 )
   cnt.gc[bin] += one(Int16)
   cnt
end

#=
# Combined Bias Correction

mutable struct OmniBiasCounter <: ReadCounter
   count::Float64
   map::Dict{UInt16,Int32}
   gc::Vector{Int16}
   isadjusted::Bool   
end
=#


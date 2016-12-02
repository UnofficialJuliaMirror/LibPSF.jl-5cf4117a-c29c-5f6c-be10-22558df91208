#LibPSF: Base definitions
#-------------------------------------------------------------------------------

#=TODO:

Arrays: Resize & write instead of using push!()???
rename: size => _size?
remove: display, show

=#


#==Constants
===============================================================================#

const SECTION_HEADER = 0
const SECTION_TYPE   = 1
const SECTION_SWEEP  = 2
const SECTION_TRACE  = 3
const SECTION_VALUE  = 4

const CHUNKID_VALUESECTIONEND = 15

#Type identifiers
const TYPEID_INT8 = 1
const TYPEID_STRING = 2
const TYPEID_ARRAY = 3
const TYPEID_INT32 = 5
const TYPEID_DOUBLE = 11
const TYPEID_COMPLEXDOUBLE = 12
const TYPEID_STRUCT = 16


#==Main Types
===============================================================================#
immutable DE{T}; end; #Dispatchable element
DE(v::Int) = DE{v}();

#Dictionary used to describe PSF properties:
typealias PropDict Dict{String, Any}

abstract Struct #Dummy type used to dispatch function calls

#Structure used to return Struct data.
typealias StructDict Dict{String, Any}

#Basic value mapping types:
typealias TraceIDOffsetMap Dict{Int, Int}
typealias NameIdMap Dict{String, Int} #Maps string to array index
typealias NameIndexMap Dict{String, Int} #Maps string to array index ?REDUNDANT

abstract Chunk #Basically means "Element" of a PSF file
abstract Container #<: Chunk #Has a Vector{Chunk}.

typealias ChunkFilter Vector{Chunk} #Originally "Filter"

#Chunk mapping
typealias IdMap Dict{Int, Chunk}

#Basic PSF file elements
#-------------------------------------------------------------------------------

#Indicies... types used for dispatching:
immutable Index; end
immutable TraceIndex; end

type ZeroPad <: Chunk
end

type Property <: Chunk
	name::String
	value::Any #Scalar value
end
Property() = Property("", nothing)

#PSFFile placeholder structure... trying to change API not to need this.
type PSFFile
	something::Int
end

type PropertyBlock
	prop::PropDict
end
PropertyBlock() = PropertyBlock(PropDict())

#Describes/names a data type:
type DataTypeDef <: Chunk
	id::Int
	name::String
	datatypeid::Int
	properties::PropertyBlock
	structdef #::StructDef - dont' know how to make cyclical types
	_datasize::Int
end
DataTypeDef() = DataTypeDef(0, "", 0, PropertyBlock(), StructDef(0), 0)

type StructDef
	childlist::Vector{DataTypeDef}
	_datasize::Int
end
StructDef(_datasize::Int) = StructDef(DataTypeDef[], _datasize)
StructDef() = StructDef(0)

#Points to a definition of a data type:
type DataTypeRef <: Chunk
	id::Int
	name::String
	datatypeid::Int
	properties::PropertyBlock
	structdef::StructDef
	psf::PSFFile #Is this actually needed???
end
DataTypeRef(psf::PSFFile) = DataTypeRef(0, "", 0, PropertyBlock(), StructDef(0), psf)

type NonSweepValue <: Chunk
	id::Int
	name::String
	valuetypeid::Int
	value::Any
	propblock::PropertyBlock
	psf::PSFFile #Is this actually needed???
end
NonSweepValue(psf::PSFFile) = NonSweepValue(0, "", 0, 0, PropertyBlock(), psf)


#PSF groups (Collects PSF sweep values.  Think each group represents a sweep.)
#-------------------------------------------------------------------------------
type GroupDef <: Chunk
	id::Int
	name::String
	nchildren::Int
	childlist::Vector{DataTypeRef}
	indexmap::TraceIDOffsetMap
	namemap::NameIdMap
	psf::PSFFile #Is this actually needed???
end
GroupDef(psf::PSFFile) = GroupDef(0, "", 0, DataTypeRef[], TraceIDOffsetMap(), NameIdMap(), psf)

#PSF file sections
#-------------------------------------------------------------------------------
abstract Section <: Container

type SectionInfo
	offset::UInt32
	size::Int
end
SectionInfo() = SectionInfo(0,0)

immutable SimpleSection{ID} <: Section #Called "SimpleContainer"
	info::SectionInfo
	childlist::Vector{Chunk}
end
(::Type{SimpleSection{ID}}){ID}(info::SectionInfo) =
	SimpleSection{ID}(info, Chunk[])
(::Type{SimpleSection{ID}}){ID}() = SimpleSection{ID}(SectionInfo(), Chunk[])

immutable IndexedSection{ID} <: Section #Called "IndexedContainer"
	info::SectionInfo
	childlist::Vector{Chunk}
	idmap::IdMap
	namemap::NameIndexMap
end
(::Type{IndexedSection{ID}}){ID}(info::SectionInfo) =
	IndexedSection{ID}(info, Chunk[], IdMap(), NameIndexMap())
(::Type{IndexedSection{ID}}){ID}() = IndexedSection{ID}(SectionInfo())

typealias HeaderSection SimpleSection{SECTION_HEADER}
typealias SweepSection SimpleSection{SECTION_SWEEP}

typealias TypeSection IndexedSection{SECTION_TYPE}
typealias TraceSection IndexedSection{SECTION_TRACE}
typealias ValueSectionNonSweep IndexedSection{SECTION_VALUE}

Section(::DE{SECTION_TYPE}, info::SectionInfo) = TypeSection(deepcopy(info))
Section(::DE{SECTION_TRACE}, info::SectionInfo) = TraceSection(deepcopy(info))
Section{V}(::DE{V}, info::SectionInfo) = SimpleSection{V}(deepcopy(info))
Section(v::Int, info::SectionInfo) = Section(DE(v), info)

type ValueSectionSweep <: Section
	info::SectionInfo
	windowsize::Int
#	childlist::Vector{Chunk} #Don't see this...
	valuesize::Int
	ntraces::Int #Does not appear to be used
	offsetmap::TraceIDOffsetMap
	curpos::Int #const char* m_valuebuf
	endpos::Int #const char* endbuf
end
ValueSectionSweep(info::SectionInfo, windowsize::Int) =
	ValueSectionSweep(deepcopy(info), windowsize, #Chunk[],
	0, 0, TraceIDOffsetMap(), 0, 0)
ValueSectionSweep(info::SectionInfo, windowsize::Integer) =
	ValueSectionSweep(info, Int(windowsize))
ValueSectionSweep() = ValueSectionSweep(SectionInfo(), 0)

#PSF reader: Main object
#-------------------------------------------------------------------------------
#Replaces PSFDataset/PSFFile:
type DataReader
	io::IOStream
	filepath::String #Informative only
	properties::PropDict
	types::Nullable{TypeSection}
	sweeps::Nullable{SweepSection}
	traces::Nullable{TraceSection}
	sweepvalues::Nullable{ValueSectionSweep}
	nonsweepvalues::Nullable{ValueSectionNonSweep}
	filesize::Int
end
function DataReader(io::IOStream, filepath::String="")
	return DataReader(io, filepath, PropDict(), nothing, nothing,
		nothing, nothing, nothing, 0)
end

#=PSFDataset: Main object (Original Hierarchy)
   .m_psf::PSFFile: 
		.m_header::HeaderSection
		.m_types::TypeSection
		.m_sweeps::SweepSection
		.m_traces::TraceSection
		.m_sweepvalues::ValueSectionSweep
		.m_nonsweepvalues::ValueSectionNonSweep
=#

#==More constructors
===============================================================================#
PSFFile{T<:Section}(::Type{T}) = PSFFile(0)

#Exception generators (TODO: Define exception types):
NotSuportedError(msg::String) = "Not yet supported: $msg."
IncorrectChunk(chunktype::Integer) = "Incorrect Chunk: $chunktype"


#==Type identification functions
===============================================================================#

#psfdata_type: Returns actual data type
#Adapted from: DataTypeDef::new_vector()
function psfdata_type(datatypeid::Int)
#@show :psfdata_type, datatypeid
	if TYPEID_INT8 == datatypeid
		return UInt8
	elseif TYPEID_INT32 == datatypeid
		return UInt32
	elseif TYPEID_DOUBLE == datatypeid
		return Float64
	elseif TYPEID_COMPLEXDOUBLE == datatypeid
		return Complex{Float64}
	elseif TYPEID_STRUCT == datatypeid
		return Struct
	else
		throw("Unknown type: $datatypeid")
	end
end
psfdata_type(def::DataTypeDef) = psfdata_type(def.datatypeid)

#Adapted from: psfdata_size
function psfdata_size(datatypeid::Int)
	if TYPEID_STRUCT == datatypeid #Not supported
		throw("Unknown type: $datatypeid")
	end
	return max(4, sizeof(psfdata_type(datatypeid)))
end

#chunkid: Usually defined as "type" in types <: Chunk
chunkid(::Type{DataTypeDef}) = 16
chunkid(::Type{DataTypeRef}) = 16
chunkid(::Type{NonSweepValue}) = 16
chunkid(::Type{GroupDef}) = 17
chunkid(::Type{Index}) = 19
chunkid(::Type{TraceIndex}) = 19
chunkid(::Type{ZeroPad}) = 20

chunkid{T<:Section}(::Type{T}) = 21

#From: Property::deserialize
function propertytype(chunktype::Int)
	if 33 == chunktype
		return String
	elseif 34 == chunktype
		return Int32
	elseif 35 == chunktype
		return Float64
	else
		throw("Unkown property type: $chunktype")
	end
end
propertytype(chunktype::Integer) = propertytype(Int(chunktype))


ischunk{T}(chunktype::Int, ::Type{T}) = throw("Not supported: ischunk($chunktype, $T)")
ischunk{T<:Chunk}(chunktype::Int, ::Type{T}) = chunkid(T)==chunktype
#static Property::ischunk
function ischunk(chunktype::Int, ::Type{Property})
	return (chunktype >= 33) && (chunktype <= 35)
end
ischunk{T}(chunktype::Integer, ::Type{T}) = ischunk(Int(chunktype), T)


#==Factories
===============================================================================#
#=
Factories create data objects for a given PSF file element, depending on
requested type id number.
=#

#HeaderSection::child_factory
function child_factory(chunktype::Int, ::Type{HeaderSection})
	if ischunk(chunktype, Property)
		return Property()
	elseif 1 == chunktype
		return nothing
	else
		throw(IncorrectChunk(chunktype))
	end
end

#TypeSection::child_factory
function child_factory(chunktype::Int, ::Type{TypeSection})
	if ischunk(chunktype, DataTypeDef)
		return DataTypeDef()
	else
		throw(IncorrectChunk(chunktype))
	end
end

#SweepSection::child_factory
function child_factory(chunktype::Int, ::Type{SweepSection})
	if ischunk(chunktype, DataTypeRef)
		return DataTypeRef(PSFFile(SweepSection))
	elseif 3 == chunktype
		return nothing
	else
		throw(IncorrectChunk(chunktype))
	end
end

#TraceSection::child_factory
function child_factory(chunktype::Int, ::Type{TraceSection})
	if ischunk(chunktype, DataTypeRef)
		return DataTypeRef(PSFFile(TraceSection))
	elseif ischunk(chunktype, GroupDef)
		return GroupDef(PSFFile(TraceSection))
	else
		throw(IncorrectChunk(chunktype))
	end
end

#ValueSectionNonSweep::child_factory
function child_factory(chunktype::Int, ::Type{ValueSectionNonSweep})
	if ischunk(chunktype, NonSweepValue)
		return NonSweepValue(PSFFile(ValueSectionNonSweep))
	else
		throw(IncorrectChunk(chunktype))
	end
end

#GroupDef::child_factory
function child_factory(chunktype::Int, ::Type{GroupDef})
	if ischunk(chunktype, DataTypeRef)
		return DataTypeRef(PSFFile(TraceSection))
	else
		throw(IncorrectChunk(chunktype))
	end
end

#StructDef::child_factory
function child_factory(chunktype::Int, ::Type{StructDef})
	if ischunk(chunktype, DataTypeDef)
		return DataTypeDef()
	elseif 18 == chunktype
		return nothing
	else
		throw(IncorrectChunk(chunktype))
	end
end

child_factory{T}(chunktype::Int, ::Type{T}) = throw(ArgumentError("child_factory($chunktype, $T)"))
child_factory{T}(chunktype::Integer, ::Type{T}) = child_factory(Int(chunktype), T)


#==Accessors
===============================================================================#

#DataTypeRef-based operations
#-------------------------------------------------------------------------------
#DataTypeRef::get_datatype()
get_datatype(ref::DataTypeRef, tsection::TypeSection) =
	tsection.idmap[ref.datatypeid]::DataTypeDef #throw exception if not correct type

#Returns actual data type
psfdata_type(ref::DataTypeRef, tsection::TypeSection) =
	psfdata_type(get_datatype(ref, tsection))

datasize(ref::DataTypeRef, tsection::TypeSection) =
	get_datatype(ref, tsection)._datasize

#GroupDef::get_child / GroupDef::get_child_index
get_child(grp::GroupDef, name::String) = grp.childlist[grp.namemap[name]]

#Container::get_child
#TraceSection/TypeSection
get_child(section::IndexedSection, name::String) = section.childlist[section.namemap[name]]

#IndexedContainer::get_child
get_child(section::IndexedSection, id::Int) = section.idmap[id]

function get_typedef(section::TypeSection, id::Int)
	return def = get_child(section, id)::DataTypeDef
end


#==File validation functions
===============================================================================#
#PSFFile::validate
function validate(r::DataReader)
	const STAMP = "Clarissa"
	buf = Array(UInt8, length(STAMP))
	seek(r.io, r.filesize-12)
	nb = readbytes!(buf, r.io, UInt8, nb=length(STAMP))

	if nb != length(STAMP) || String(buf) != "Clarissa"
		throw("Incomplete/corrupt file.")
	end
end

#==Read functions
===============================================================================#
#GET_INT32(buf)
Base.read{T<:Integer}(r::DataReader, ::Type{T}) = ntoh(read(r.io, T))

#PSFInt8Scalar::deserialize
function Base.read{T<:Union{UInt8,Int8}}(r::DataReader, ::Type{T})
	data = read(r.io, UInt8, 4)
	return data[4]
end

#GET_DOUBLE(dest, buf)... but keeps value as a float:
Base.read(r::DataReader, ::Type{Float64}) = reinterpret(Float64, ntoh(read(r.io, UInt64)))
Base.read(r::DataReader, ::Type{Complex{Float64}}) = Complex{Float64}(read(r, Float64),read(r, Float64))


#==Generate friendly show functions
===============================================================================#
#Don't display module name on show:
Base.show(io::IO, ::Type{Chunk}) = print(io, "Chunk")
Base.show(io::IO, ::Type{Index}) = print(io, "Index")
Base.show(io::IO, ::Type{TraceIndex}) = print(io, "TraceIndex")
Base.show(io::IO, ::Type{Property}) = print(io, "Property")
Base.show(io::IO, ::Type{PropertyBlock}) = print(io, "PropertyBlock")
Base.show(io::IO, ::Type{SectionInfo}) = print(io, "SectionInfo")
Base.show(io::IO, ::Type{DataTypeDef}) = print(io, "DataTypeDef")
Base.show(io::IO, ::Type{DataTypeRef}) = print(io, "DataTypeRef")
Base.show(io::IO, ::Type{PSFFile}) = print(io, "PSFFile")
Base.show(io::IO, ::Type{StructDef}) = print(io, "StructDef")
Base.show(io::IO, ::Type{GroupDef}) = print(io, "GroupDef")

Base.show(io::IO, ::Type{HeaderSection}) = print(io, "HeaderSection")
Base.show(io::IO, ::Type{TypeSection}) = print(io, "TypeSection")
Base.show(io::IO, ::Type{SweepSection}) = print(io, "SweepSection")
Base.show(io::IO, ::Type{TraceSection}) = print(io, "TraceSection")
Base.show(io::IO, ::Type{ValueSectionSweep}) = print(io, "ValueSectionSweep")
Base.show(io::IO, ::Type{ValueSectionNonSweep}) = print(io, "ValueSectionNonSweep")

#Last Line

/++
Alis Common Data Types
+/
module alis.common;

import alis.utils;

import std.string,
			 std.array,
			 std.traits,
			 std.range,
			 std.conv,
			 std.meta,
			 std.format,
			 std.typecons,
			 std.algorithm,
			 std.digest.crc;

import alis.compiler.common;

import meta;

public import alis.compiler.ast.rst : RExpr;
public import alis.compiler.semantic.common : AValCT;

debug import std.stdio;

/// Visibility specifier
/// first rightmost bit -> 1 if can read
/// second rightmost bit -> 1 if can write
public enum Visibility : ubyte{
	Default = 0,
	IPub = 1,
	Pub = 2,
}

/// `"this"`
public enum This = "this";

/// Alis value, with ADataType
public struct AVal{
	void[] data; /// the data
	ADataType type = ADataType.ofNoInit; /// data type

	/// Returns: true if this can be implicitly casted to target type
	public bool canCastTo(const ADataType target,
			IdentU[] ctx = null) pure {
		if (ctx is null)
			ctx = [IdentU.init];
		if (type.type == ADataType.Type.IntX ||
				type.type == ADataType.Type.UIntX){
			if (target.type == ADataType.Type.IntX){
				switch (target.x){
					static foreach (T; SignedInts){
						case T.sizeof * 8:
							return as!T(ctx).isVal;
					}
					default: break;
				}
			} else
			if (target.type == ADataType.Type.UIntX){
				switch (target.x){
					static foreach (T; UnsignedInts){
						case T.sizeof * 8:
							return as!T(ctx).isVal;
					}
					default: break;
				}
			}
		}
		return type.canCastTo(target, ctx);
	}

	/// converts this value into `target` type
	/// only call this if `this.canCastTo(target)`, or bad things will happen
	/// Returns: converted value, or nothing if cannot be done
	public OptVal!AVal to(const ADataType target,
			IdentU[] ctx = null) pure {
		assert (this.canCastTo(target, ctx));
		if (ctx is null)
			ctx = [IdentU.init];
		AVal ret;
		if (type == target)
			return this.OptVal!AVal;
		switch (target.type){
			case ADataType.Type.Struct:
				OptVal!(void[]) bytes = target.structS.buildVal(this, ctx);
				if (bytes.isVal)
					return AVal(target, bytes.val).OptVal!AVal;
				break;
			case ADataType.Type.Union:
				OptVal!(void[]) bytes = target.unionS.buildVal(this, ctx);
				if (bytes.isVal)
					return AVal(target, bytes.val).OptVal!AVal;
				break;
			default:
				break;
		}

		final switch (type.type){
			case ADataType.Type.IntX:
			case ADataType.Type.UIntX:
			case ADataType.Type.Char:
				switch (target.type){
					case ADataType.Type.IntX:
						switch (target.x){
							static foreach (Type; SignedInts){
								case Type.sizeof * 8:
									OptVal!Type r = this.as!Type(ctx);
									if (r.isVal)
										return OptVal!AVal(r.val.AVal);
									return OptVal!AVal();
							}
							default:
								return OptVal!AVal();
						}
					case ADataType.Type.UIntX:
						switch (target.x){
							static foreach (Type; UnsignedInts){
								case Type.sizeof * 8:
									OptVal!Type r = this.as!Type(ctx);
									if (r.isVal)
										return OptVal!AVal(r.val.AVal);
									return OptVal!AVal();
							}
							default:
								return OptVal!AVal();
						}
					case ADataType.Type.FloatX:
						switch (target.x){
							static foreach (Type; Floats){
								case Type.sizeof * 8:
									OptVal!Type r = this.as!Type(ctx);
									if (r.isVal)
										return OptVal!AVal(r.val.AVal);
									return OptVal!AVal();
							}
							default:
								return OptVal!AVal();
						}
					case ADataType.Type.Char:
						OptVal!ubyte r = this.as!ubyte(ctx);
						if (r.isVal)
							return OptVal!AVal(r.val.AVal);
						return OptVal!AVal();
					default:
						return OptVal!AVal();
				}
			case ADataType.Type.FloatX:
				switch (target.x){
					static foreach (Type; Floats){
						case Type.sizeof * 8:
							OptVal!Type r = this.as!Type(ctx);
							if (r.isVal)
								return OptVal!AVal(r.val.AVal);
							return OptVal!AVal();
					}
					default:
						return OptVal!AVal();
				}
			case ADataType.Type.Bool:
				if (target.type == ADataType.Type.Bool)
					return this.OptVal!AVal;
				switch (target.type){
					case ADataType.Type.IntX:
						switch (target.x){
							static foreach (Type; SignedInts){
								case Type.sizeof * 8:
									return (cast(ubyte[])data)[0] == 0
										? (cast(Type)0).AVal.OptVal!AVal
										: (cast(Type)1).AVal.OptVal!AVal;
							}
							default:
								return OptVal!AVal();
						}
					case ADataType.Type.UIntX:
						switch (target.x){
							static foreach (Type; UnsignedInts){
								case Type.sizeof * 8:
									return (cast(ubyte[])data)[0] == 0
										? (cast(Type)0).AVal.OptVal!AVal
										: (cast(Type)1).AVal.OptVal!AVal;
							}
							default:
								return OptVal!AVal();
						}
					default:
						return OptVal!AVal();
				}
			case ADataType.Type.Array:
				switch (target.type){
					case ADataType.Type.Slice:
						return AVal(target, data[0 .. null.sizeof + size_t.sizeof].dup)
							.OptVal!AVal;
					case ADataType.Type.Array:
						return AVal(target, data.dup).OptVal!AVal;
					default:
						return OptVal!AVal();
				}
			case ADataType.Type.Slice:
			case ADataType.Type.Ref:
			case ADataType.Type.Fn:
				return AVal(type, data.dup).OptVal!AVal;
			case ADataType.Type.NoInit:
				return this.OptVal!AVal;
			case ADataType.Type.Struct:
				if (target.type == ADataType.Type.Struct){
					if (this.type.structS == target.structS)
						return AVal(target, data.dup).OptVal!AVal;
					if (!this.type.structS.isUnique){
						OptVal!(void[]) buildVal = target.structS.buildVal(this, ctx);
						if (buildVal.isVal)
							return AVal(target, buildVal.val).OptVal!AVal;
					}
				}
				AStruct* symC = this.type.structS;
				if (!symC.hasBase(ctx) || !symC.types[0].canCastTo(target, ctx))
					return OptVal!AVal();
				return AVal(symC.types[0], data[0 .. symC.types[0].sizeOf])
					.to(target, ctx);
			case ADataType.Type.Union:
				if (target.type == ADataType.Type.Union){
					if (this.type.unionS == target.unionS)
						return AVal(target, data.dup).OptVal!AVal;
				}
				AUnion* symC = this.type.unionS;
				immutable size_t memId = data[symC.sizeOfField .. $].as!size_t;
				if (!symC.hasBase(ctx) ||
						memId != symC.names[This][0])
					return OptVal!AVal();
				return AVal(symC.types[memId], data[0 .. symC.types[memId].sizeOf])
					.OptVal!AVal;
			case ADataType.Type.Enum:
				return AVal(type.enumS.type, data).to(target, ctx);
		}
		return ret.OptVal!AVal;
	}

	/// decodes this data into a type `T`
	/// Returns: Optional value of type `T`
	public OptVal!T as(T...)(IdentU[] ctx = [IdentU.init]) pure if (
			T.length && allSatisfy!(isType, T)){
		static if (T.length == 1){
			assert (type.sizeOf == data.length);
			static if (std.traits.isNumeric!(T[0])){
				static if (isFloatingPoint!(T[0])){
					if (!type.canCastTo(ADataType.of!T, ctx))
						return OptVal!T();
					if (type.type != ADataType.Type.FloatX ||
							type.x > T[0].sizeof * 8)
						return OptVal!(T[0])();
					switch (data.length){
						static foreach (Type; Floats){
							static if (T[0].sizeof >= Type.sizeof){
								case Type.sizeof:
									return OptVal!(T[0])(data.as!Type);
							}
						}
					default:
						debug stderr.writefln!"invalid data found in AVal.as";
						return OptVal!(T[0])();
					}
				} else {
					if (type.type == ADataType.Type.IntX){
						ptrdiff_t num;
signedSwitch:
						switch (data.length){
							static foreach (Type; SignedInts){
								case Type.sizeof:
									num = data.as!Type;
									break signedSwitch;
							}
							default:
							debug stderr.writefln!"invalid data found in AVal.as";
							return OptVal!(T[0])();
						}
						if (num < (T[0]).min || num > (T[0]).max)
							return OptVal!(T[0])();
						return OptVal!(T[0])(cast(T[0])num);
					} else
						if (type.type == ADataType.Type.UIntX){
							size_t num;
unsignedSwitch:
							switch (data.length){
								static foreach (Type; UnsignedInts){
									case Type.sizeof:
										num = data.as!Type;
										break unsignedSwitch;
								}
								default:
								debug stderr.writefln!"invalid data found in AVal.as";
								return OptVal!(T[0])();
							}
							if (num < (T[0]).min || num > (T[0]).max)
								return OptVal!(T[0])();
							return OptVal!(T[0])(cast(T[0])num);
						}
				}

			} else
			static if (is (T[0] == char)){
				return OptVal!(T[0])((cast(char[])data)[0]);
			} else
			static if (isBoolean!T){
				if (type.type != ADataType.Type.Bool)
					return OptVal!(T[0])();
				return OptVal!(T[0])((cast(ubyte[])data)[0] != 0);

			} else
			static if (isPointer!T){
				static assert (false, "AVal for pointers not yet implemented");

			} else
			static if (is (T == string) || (isArray!T && is(ElementType!T == dchar))){
				if (type != ADataType.ofString)
					return OptVal!(T[0])();
				char* ptr = data[0 .. ptrdiff_t.sizeof].as!(char*);
				size_t len = data[ptrdiff_t.sizeof .. $].as!size_t;
				return OptVal!(T[0])(cast(string)ptr[0 .. len]);

			} else
			static if (isArray!T){
				if (type.type != ADataType.Type.Slice &&
						type.type != ADataType.Type.Array)
					return OptVal!(T[0])();
				ADataType elemT = *type.refT;
				if (elemT != ADataType.of!(ElementType!T))
					return OptVal!(T[0])();
				ElementType!T* ptr = data[0 .. ptrdiff_t.sizeof].as!(ElementType!T*);
				size_t len = data[ptrdiff_t.sizeof .. $].as!size_t;
				return OptVal!T(cast(T[0])ptr[0 .. len]);

			} else
			static if (isFunction!(T[0]) || isFunctionPointer!(T[0])){
				static assert (false, "AVal.as does not suppport Fn yet");
			} else
			static if (is (T[0] == struct)){
				static assert (false, "AVal.as does not suppport Struct yet");
			} else
			static if (is (T[0] == union)){
				static assert (false, "AVal.as does not suppport Union yet");
			} else
			static if (is (T[0] == enum)){
				static assert (false, "AVal.as does not suppport Enum yet");
			} else {
				static assert (false,
						T.stringof.format!"Unsupported data type for AVal.as %s");
			}
		} else {
			static assert (false, "AVal does not yet support Sequences fully");
		}
		assert (false);
	}

	/// encodes some data
	/// Returns: Optional AVal if done, empty if failed
	public static OptVal!AVal of(T)(T val) pure {
		static if (std.traits.isNumeric!T){
			void[] d = val.asBytes;
			ADataType t = ADataType.of!T;
			assert (t.sizeOf >= d.length);
			return AVal(t, d).OptVal!AVal;
		} else
		static if (is (T == char)){
			return AVal(ADataType.ofChar, [val]).OptVal!AVal;
		} else
		static if (isBoolean!T){
			return AVal(ADataType.ofBool, val ? [true] : [false]).OptVal!AVal;
		} else
		static if (isPointer!T){
			static assert (false, "AVal for pointers not yet implemented");
		} else
		static if (is (T == string) || isStaticArray!T){
			void[] d = new void[size_t.sizeof * 2];
			d[0 .. size_t.sizeof] = val.ptr.asBytes;
			d[size_t.sizeof .. $] = val.length.asBytes;
			ADataType t = ADataType.of!T;
			assert (t.sizeOf == d.length);
			return AVal(t, d).OptVal!AVal;
		} else
		static if (isArray!T){
			void[] d = new void[size_t.sizeof * 3];
			d[0 .. size_t.sizeof] = val.ptr.asBytes;
			d[size_t.sizeof .. 2 * size_t.sizeof] = val.length.asBytes;
			d[2 * size_t.sizeof .. $][] = max(val.capacity, val.length).asBytes;
			ADataType t = ADataType.of!T;
			assert (t.sizeOf == d.length);
			return AVal(t, d).OptVal!AVal;
		} else
		static if (isFunction!(T[0]) || isFunctionPointer!(T[0])){
			static assert (false, "AVal.of does not suppport Fn yet");
		} else
		static if (is (T[0] == struct)){
			static assert (false, "AVal.of does not suppport Struct yet");
		} else
		static if (is (T[0] == union)){
			static assert (false, "AVal.of does not suppport Union yet");
		} else
		static if (is (T[0] == enum)){
			static assert (false, "AVal.of does not suppport Enum yet");
		} else {
			static assert (false, "Unsupported data type for AVal.of");
		}
		assert (false);
	}

	public string toString() const pure {
		import alis.utils : as, asBytes;
		if (this.type == ADataType.ofString){
			return (cast(AVal)this).as!string.val;
		}
		final switch (type.type){
			case ADataType.Type.IntX:
				switch (type.x){
					static foreach (T; SignedInts){
						case T.sizeof * 8:
							return format!("%d_I" ~ (T.sizeof * 8).to!string)
								(alis.utils.as!T(data));
					}
					default:
						assert (false);
				}
				break;
			case ADataType.Type.UIntX:
				switch (type.x){
					static foreach (T; UnsignedInts){
						case T.sizeof * 8:
							return format!("%d_U" ~ (T.sizeof * 8).to!string)
								(alis.utils.as!T(data));
					}
					default:
						assert (false);
				}
				break;
			case ADataType.Type.FloatX:
				switch (type.x){
					static foreach (T; Floats){
						case T.sizeof * 8:
							return format!("%f_F" ~ (T.sizeof * 8).to!string)
								(alis.utils.as!T(data));
					}
					default:
						assert (false);
				}
				break;
			case ADataType.Type.Char:
				return [(cast(char[])data)[0]];
				break;
			case ADataType.Type.Bool:
				return (cast(ubyte[])data)[0] == 0 ? "false" : "true";
				break;
			case ADataType.Type.Slice:
			case ADataType.Type.Array:
				void[] buf = (cast(void*)data.ptr)
					[0 .. cast(size_t)(data.ptr + null.sizeof)];
				size_t eSize = type.refT.sizeOf;
				(buf.length / eSize).iota
					.map!(
						i => AVal(*type.refT, buf[i * eSize .. (i + 1) * eSize]).toString)
					.join(", ")
					.format!"[%s]";
				break;
			case ADataType.Type.Ref:
			case ADataType.Type.Fn:
				return (cast(ushort[])data).format!"<%(%04x %):%s>"(type.toString);
				break;
			case ADataType.Type.Struct:
				Appender!string ret;
				size_t offset = 0;
				ret.put("{");
				foreach (size_t id, const ADataType type; type.structS.types){
					AVal val = AVal(type, data[offset .. offset + type.sizeOf]);
					offset += type.sizeOf;
					foreach (string name, const size_t[] ids; type.structS.names){
						ptrdiff_t index = ids.countUntil(id);
						if (index < 0) continue;
						ret.put(name);
						if (ids.length > 1){
							ret.put("[");
							ret.put(index.to!string);
							ret.put("]");
						}
						ret.put(" ");
					}
					ret.put("= ");
					ret.put(val.toString);
					ret.put(",");
				}
				ret.put("}");
				return ret.data;
			case ADataType.Type.Union:
				immutable size_t fieldSize = type.unionS.sizeOfField;
				immutable size_t memId = data[fieldSize .. $].as!size_t;
				AVal val = AVal(type.unionS.types[memId],
							data[0 .. type.unionS.types[memId].sizeOf]);
				if (type.unionS.isUnnamed)
					return val.toString;
				Appender!string ret;
				ret.put("{");
				foreach (string name, const size_t[] ids; type.unionS.names){
					ptrdiff_t index = ids.countUntil(memId);
					if (index < 0) continue;
					ret.put(name);
					if (ids.length > 1){
						ret.put("[");
						ret.put(index.to!string);
						ret.put("]");
					}
					ret.put(" ");
				}
				ret.put("= ");
				ret.put(val.toString);
				ret.put("}");
				return ret.data;
			case ADataType.Type.Enum:
				foreach (size_t i; 0 .. type.enumS.memId.length){
					if (data == type.enumS.memVal[i])
						return type.enumS.ident.map!(id => id.toString).join(".")
							.format!"%s.%s"(type.enumS.memId[i]);
				}
				return AVal(type.enumS.type, data).toString;
			case ADataType.Type.NoInit:
				return "$noinitval";
				break;
		}
		return format!"{type: %s, data: %s}"(type, cast(ubyte[])data);
	}

	/// constructor
	this (ADataType type, void[] data) pure {
		assert (data.length == type.sizeOf,
				format!"%d != %d"(data.length, type.sizeOf));
		this.type = type;
		this.data = data;
	}
	/// ditto
	this(ADataType type, const void[] data) pure {
		this (type, data.dup);
	}
	/// ditto
	this(const ADataType type, void[] data) pure {
		this (type.copy, data);
	}
	/// ditto
	this(const ADataType type, const void[] data) pure {
		this (type.copy, data.dup);
	}

	/// ditto
	this(T...)(T val) pure if (T.length && allSatisfy!(isType, T) &&
			!is (T[0] : const ADataType)){
		this.type = ADataType.of!T;
		static if (T.length == 1){
			OptVal!AVal v = of(val);
			assert (v.isVal);
			this = v.val;
		} else {
			enum SizeOfSeq = ADataType.of!T.sizeOf;
			data = new void[SizeOfSeq];
			static foreach (size_t I; 0 .. T.length){{
				enum PrefixSum = ADataType.of!(T[0 .. I]).sizeOf;
				enum Size = ADataType.of!(T[I]).sizeOf;
				AVal encoded = encode(val[i]);
				assert(encoded.type == type.seqT[i]);
				data[PrefixSum .. PrefixSum + Size] = encoded.data;
			}}
		}
	}
}

///
unittest{
	assert("hello world".AVal.as!string.val == "hello world");
	assert(AVal('a').as!char.val == 'a');
	assert(AVal(5.5).as!double.val == 5.5);
	assert(AVal(5).as!int.val == 5);
	assert(AVal(5U).as!ulong.val == 5);
	assert(AVal(5).as!long.val == 5);
	assert(true.AVal.as!bool.val == true);
	assert(false.AVal.as!bool.val == false);
	assert([1, 2].AVal.as!(int[]).val == [1, 2]);
}

/// identifier node unit
public struct IdentU{
public:
	/// identifier
	string ident = "_";
	/// parameters, if any
	AValCT[] params;
	/// constructor
	this (string ident, AValCT[] params = null) pure {
		this.ident = ident;
		this.params = params.dup;
	}
	string toString() const pure {
		if (params)
			return format!"%s(%s)"(ident,
					params.map!(p => p.toString).join(","));
		return ident;
	}
	//bool opEquals(const IdentU rhs) const pure {
	bool opEquals()(auto ref const IdentU rhs) const pure {
		if (ident != rhs.ident || params.length != rhs.params.length)
			return false;
		foreach (i, param; params){
			if (param != rhs.params[i])
				return false;
		}
		return true;
	}
	size_t toHash() const {
		return tuple(ident, params).toHash;
	}
}

/// Whether an IdentU[] is to [IdentU.init]
public bool isNoId()(auto ref const IdentU[] ident){
	return ident.length == 1 && ident[0] == IdentU.init;
}

/// Returns: IdentU[] as a human readable string
public string toString()(const auto ref IdentU[] id) pure {
	return id.map!(i => i.toString).join(".");
}

/// a symbol
public struct ASymbol{
	/// Whether this is complete
	bool isComplete = false;
	/// corresponding ASTNode (can be null)
	ASTNode ast;
	/// Returns: whether this is a callable (template or function)
	@property bool isCallable() const pure {
		final switch (type){
			case Type.Struct:
			case Type.Union:
			case Type.Enum:
			case Type.Var:
			case Type.Import:
			case Type.EnumConst:
			case Type.UTest:
				return false;
			case Type.Alias:
				return false; // TODO: implement for Alias
			case Type.Fn:
			case Type.Template:
				return true;
		}
	}

	///Returns: true if this is a value
	bool isVal() const pure {
		final switch (type){
			case ASymbol.Type.Struct:
			case ASymbol.Type.Union:
			case ASymbol.Type.Enum:
			case ASymbol.Type.Import:
			case ASymbol.Type.UTest:
			case ASymbol.Type.Template:
				return false;
			case ASymbol.Type.Var:
			case ASymbol.Type.EnumConst:
			case ASymbol.Type.Fn:
				return true;
			case ASymbol.Type.Alias:
				assert (false, "isVal on Alias is undecided");
		}
	}

	/// Returns: data type of value, if `isVal`
	OptVal!ADataType valType() pure {
		final switch (type){
			case ASymbol.Type.Struct:
			case ASymbol.Type.Union:
			case ASymbol.Type.Enum:
			case ASymbol.Type.Import:
			case ASymbol.Type.UTest:
			case ASymbol.Type.Template:
				return OptVal!ADataType();
			case ASymbol.Type.Var:
				return varS.type.OptVal!ADataType;
			case ASymbol.Type.EnumConst:
				return enumCS.type.OptVal!ADataType;
			case ASymbol.Type.Fn:
				return ADataType.ofFn(fnS.retT, fnS.paramsT)
					.OptVal!ADataType;
			case ASymbol.Type.Alias:
				assert (false, "valType on Alias is undecided");
		}
	}

	/// Returns: identifier, `_` if anonymous
	@property inout(IdentU[]) ident() pure inout {
		final switch (type){
			case Type.Struct:
				return structS.ident;
			case Type.Union:
				return unionS.ident;
			case Type.Enum:
				return enumS.ident;
			case Type.EnumConst:
				return enumCS.ident;
			case Type.Fn:
				return fnS.ident;
			case Type.Var:
				return varS.ident;
			case Type.Alias:
				return aliasS.ident;
			case Type.Import:
				return importS.ident;
			case Type.Template:
				return templateS.ident;
			case Type.UTest:
				return utestS.ident;
		}
		assert(false);
	}

	/// Returns: Visibility
	@property Visibility vis() pure {
		final switch (type){
			case Type.Struct:
				return structS.vis;
			case Type.Union:
				return unionS.vis;
			case Type.Enum:
				return enumS.vis;
			case Type.EnumConst:
				return enumCS.vis;
			case Type.Fn:
				return fnS.vis;
			case Type.Var:
				return varS.vis;
			case Type.Alias:
				return aliasS.vis;
			case Type.Import:
				return importS.vis;
			case Type.Template:
				return templateS.vis;
			case Type.UTest:
				return utestS.vis;
		}
		assert(false);
	}

	/// Returns: true if this symbol can be a data type
	@property bool isDType() const pure {
		final switch (type){
			case ASymbol.Type.Struct:
			case ASymbol.Type.Union:
			case ASymbol.Type.Enum:
				return true;
			case ASymbol.Type.EnumConst:
			case ASymbol.Type.Fn:
			case ASymbol.Type.Var:
			case ASymbol.Type.Import:
			case ASymbol.Type.UTest:
			case ASymbol.Type.Template:
				return false;
			case ASymbol.Type.Alias:
				return false; // TODO: implement for Alias
		}
	}

	/// Returns: this symbol, as a type, in Optional ADataType.
	/// Only valid if `this.isDType`
	@property OptVal!ADataType asType() pure {
		final switch (type){
			case ASymbol.Type.Struct:
				return ADataType.of(&structS).OptVal!ADataType;
			case ASymbol.Type.Union:
				return ADataType.of(&unionS).OptVal!ADataType;
			case ASymbol.Type.Enum:
				return ADataType.of(&enumS).OptVal!ADataType;
			case ASymbol.Type.EnumConst:
			case ASymbol.Type.Fn:
			case ASymbol.Type.Var:
			case ASymbol.Type.Import:
			case ASymbol.Type.UTest:
			case ASymbol.Type.Template:
			case ASymbol.Type.Alias:
				return OptVal!ADataType();
		}
	}

	/// possible Symbol types
	enum Type{
		Struct,
		Union,
		Enum,
		EnumConst,
		Fn,
		Var,
		Alias,
		Import,
		Template,
		UTest,
	}
	/// type of this symbol
	Type type;

	union{
		AStruct structS; /// struct for `Type.Struct`
		AUnion unionS; /// union for `Type.Union`
		AEnum enumS; /// enum for `Type.Enum`, or `Type.EnumMember`
		AEnumConst enumCS; /// enum for `Type.EnumConst`
		AFn fnS; /// function for `Type.Fn`
		AVar varS; /// variable for `Type.Var`
		AAlias aliasS; /// alias for `Type.Alias`
		AImport importS; /// import for `Type.Import`
		ATemplate templateS; /// template for `Type.Template`
		AUTest utestS; /// utest for `Type.UTest`
	}

	/// Returns: string representation, equivalent to `ASymbol.ident.toString`
	string toString() const pure {
		string ret;
		final switch (type){
			case Type.Struct:
				ret = structS.toString; break;
			case Type.Union:
				ret = unionS.toString; break;
			case Type.Enum:
				ret = enumS.toString; break;
			case Type.EnumConst:
				ret = enumCS.toString; break;
			case Type.Fn:
				ret = fnS.toString; break;
			case Type.Var:
				ret = varS.toString; break;
			case Type.Alias:
				ret = aliasS.toString; break;
			case Type.Import:
				ret = importS.toString; break;
			case Type.Template:
				ret = templateS.toString; break;
			case Type.UTest:
				ret = utestS.toString; break;
		}
		if (!isComplete)
			ret = '#' ~ ret;
		return ret;
	}

	bool opEquals()(auto ref const AStruct structS) const {
		return this.type == Type.Struct && this.structS == structS;
	}
	bool opEquals()(auto ref const AUnion unionS) const {
		return this.type == Type.Union && this.unionS == unionS;
	}
	bool opEquals()(auto ref const AEnum enumS) const {
		return (this.type == Type.Enum || this.type == Type.EnumMember) &&
			this.enumS == enumS;
	}
	bool opEquals()(auto ref const AEnumMember enumS) const {
		return (this.type == Type.Enum || this.type == Type.EnumMember) &&
			this.enumS == enumS;
	}
	bool opEquals()(auto ref const AEnumConst enumCS) const {
		return this.type == Type.EnumConst && this.enumCS == enumCS;
	}
	bool opEquals()(auto ref const AFn fnS) const {
		return this.type == Type.Fn && this.fnS == fnS;
	}
	bool opEquals()(auto ref const AVar varS) const {
		return this.type == Type.Var && this.varS == varS;
	}
	bool opEquals()(auto ref const AAlias aliasS) const {
		return this.type == Type.Alias && this.aliasS == aliasS;
	}
	bool opEquals()(auto ref const AImport importS) const {
		return this.type == Type.Import && this.importS == importS;
	}
	bool opEquals()(auto ref const ATemplate templateS) const {
		return this.type == Type.Template && this.templateS == templateS;
	}
	bool opEquals()(auto ref const AUTest utestS) const {
		return this.type == Type.UTest && this.utestS == utestS;
	}

	bool opEquals()(auto ref const ASymbol rhs) const {
		if (rhs.type != this.type || this.ident != ident)
			return false;
		final switch (type){
			case Type.Struct:
				return rhs == this.structS;
			case Type.Union:
				return rhs == this.unionS;
			case Type.Enum:
				return rhs == this.enumS;
			case Type.EnumMember:
				return rhs == this.enumS && rhs.enumMember == this.enumMember;
			case Type.EnumConst:
				return rhs == this.enumCS;
			case Type.Fn:
				return rhs == this.fnS;
			case Type.Var:
				return rhs == this.varS;
			case Type.Alias:
				return rhs == this.aliasS;
			case Type.Import:
				return rhs == this.importS;
			case Type.Template:
				return this == this.templateS;
		}
		assert (false);
	}

	/// constructor
	this (AStruct structS){
		this.type = Type.Struct;
		this.structS = structS;
	}
	/// ditto
	this (AUnion unionS){
		this.type = Type.Union;
		this.unionS = unionS;
	}
	/// ditto
	this (AEnum enumS){
		this.type = Type.Enum;
		this.enumS = enumS;
	}
	/// ditto
	this (AEnumConst enumCS){
		this.type = Type.EnumConst;
		this.enumCS = enumCS;
	}
	/// ditto
	this (AFn fnS){
		this.type = Type.Fn;
		this.fnS = fnS;
	}
	/// ditto
	this (AVar varS){
		this.type = Type.Var;
		this.varS = varS;
	}
	/// ditto
	this (AAlias aliasS){
		this.type = Type.Alias;
		this.aliasS = aliasS;
	}
	/// ditto
	this (AImport importS){
		this.type = Type.Import;
		this.importS = importS;
	}
	/// ditto
	this (ATemplate templateS){
		this.type = Type.Template;
		this.templateS = templateS;
	}
	/// ditto
	this (AUTest utestS){
		this.type = Type.UTest;
		this.utestS = utestS;
	}
}

/// Level of possible Type Casting
enum CastLevel : int{
	/// no cast needed, types are same
	None = 0,
	/// data of type `source` can be read as being `target` without copying,
	/// modifications, or slicing
	InPlace = 1,
	/// `source` type is a superset of `target` such that data of type `source`
	/// contains `target` in its starting bytes (`[0 .. target.sizeOf]`)
	/// as such, a `@target` can reference to data of type `source` safely
	Ref = 2,
	/// data needs to be copied/modified to cast from `source` to `target`
	Simple = 3,
}

/// Alis Data Type.
public struct ADataType{
	/// possible Data Types
	enum Type{
		IntX, /// an integer of X bits
		UIntX, /// an unsigned integer of X bits
		FloatX, /// a floating point number of X bits
		Char, /// a 1 byte character
		Bool, /// a boolean
		Slice, /// a slice
		Array, /// an array
		Ref, /// a reference
		Fn, /// a function
		Struct, /// a struct
		Union, /// a union
		Enum, /// an enum
		NoInit, /// `$noinit`
	}
	/// whether it is a const
	bool isConst = false;
	/// type
	Type type = Type.Struct;
	union{
		/// X-bits for `IntX`, `UIntX`, `FloatX`
		ubyte x;
		/// type being referenced, for `Ref`, `Slice`, or `Array`
		ADataType* refT;
		/// Struct reference for `Struct`
		AStruct* structS;
		/// Union reference for `Union`
		AUnion* unionS;
		/// Enum reference for `Enum`
		AEnum* enumS;
		struct{
			/// return type, for `Fn`
			ADataType* retT;
			/// parameter types, for `Fn`
			ADataType[] paramT;
		}
	}

	/// Finds CastLevel possible between `this` and `target`
	/// `ctx` is only needed for `Struct` and `Union`
	///
	/// Returns: Lowest possible `CastLevel`, or no value if not possible
	OptVal!CastLevel castability(const ADataType target,
			IdentU[] ctx = [IdentU.init]) const pure {
		switch (target.type){
			case ADataType.Type.Struct:
				if (target.structS == null){
					if (this.structS == null)
						return CastLevel.None.OptVal!CastLevel;
					break;
				}
				if (target.structS.canBuildVal(this, ctx))
					return CastLevel.Simple.OptVal!CastLevel;
				break;
			case ADataType.Type.Union:
				if (target.unionS.canBuildVal(this, ctx))
					return CastLevel.Simple.OptVal!CastLevel;
				break;
			default:
				break;
		}
main_switch:
		final switch (this.type){
			case ADataType.Type.IntX:
				if (target.type != ADataType.Type.IntX)
					break;
				if (target.x == this.x)
					return CastLevel.None.OptVal!CastLevel;
				if (target.x > this.x)
					return CastLevel.Simple.OptVal!CastLevel;
				break;

			case ADataType.Type.UIntX:
				switch (target.type){
					case ADataType.Type.UIntX:
						if (target.x == this.x)
							return CastLevel.None.OptVal!CastLevel;
						if (target.x > this.x)
							return CastLevel.Simple.OptVal!CastLevel;
						break;
					case ADataType.Type.IntX:
						if (target.x > this.x)
							return CastLevel.Simple.OptVal!CastLevel;
						break;
					default:
						break;
				}
				break;

			case ADataType.Type.FloatX:
				if (target.type != ADataType.Type.FloatX)
					break;
				if (target.x == this.x)
					return CastLevel.None.OptVal!CastLevel;
				if (target.x > this.x)
					return CastLevel.Simple.OptVal!CastLevel;
				break;

			case ADataType.Type.Char:
				switch (target.type){
					case ADataType.Type.Char:
						return CastLevel.None.OptVal!CastLevel;
					case ADataType.Type.UIntX:
						if (target.x == char.sizeof * 8)
							return CastLevel.InPlace.OptVal!CastLevel;
						goto case;
					case ADataType.Type.IntX:
						if (target.x > char.sizeof * 8)
							return CastLevel.Simple.OptVal!CastLevel;
						break;
					default:
						break;
				}
				break;

			case ADataType.Type.Bool:
				switch (target.type){
					case ADataType.Type.Bool:
						return CastLevel.None.OptVal!CastLevel;
					case ADataType.Type.UIntX:
					case ADataType.Type.IntX:
						if (target.x == bool.sizeof * 8)
							return CastLevel.InPlace.OptVal!CastLevel;
						return CastLevel.Simple.OptVal!CastLevel;
					default:
						break;
				}
				break;

			case ADataType.Type.Slice:
				if (target.type != ADataType.Type.Slice)
					break;
				OptVal!CastLevel r = this.refT.castability(*target.refT, ctx);
				if (!r.isVal || r.val > CastLevel.InPlace)
					break;
				return r.val.OptVal!CastLevel;

			case ADataType.Type.Array:
				if (target.type != ADataType.Type.Slice &&
						target.type != ADataType.Type.Array)
					break;
				OptVal!CastLevel r = this.refT.castability(*target.refT, ctx);
				if (!r.isVal || r.val > CastLevel.InPlace)
					break;
				if (target.type == ADataType.Type.Array)
					return r.val.OptVal!CastLevel;
				return CastLevel.Simple.OptVal!CastLevel;

			case ADataType.Type.Fn:
				if (target.type != ADataType.Type.Fn ||
						target.paramT.length != this.paramT.length)
					break;
				CastLevel maxLevel = CastLevel.None;
				OptVal!CastLevel r = this.refT.castability(*target.refT, ctx);
				if (!r.isVal || r.val > CastLevel.InPlace)
					break;
				maxLevel = maxLevel.max(r.val);
				foreach (size_t i; 0 .. this.paramT.length){
					r = this.paramT[i].castability(target.paramT[i], ctx);
					if (!r.isVal || r.val > CastLevel.InPlace)
						break main_switch;
					maxLevel = maxLevel.max(r.val);
				}
				return maxLevel.OptVal!CastLevel;

			case ADataType.Type.Ref:
				if (target.type == ADataType.Type.Ref){
					OptVal!CastLevel r = this.refT.castability(*target.refT, ctx);
					if (!r.isVal || r.val > CastLevel.Ref)
						break;
					return r.val.OptVal!CastLevel;
				}
				// auto de-ref case
				OptVal!CastLevel r = this.refT.castability(target, ctx);
				if (!r.isVal)
					break;
				return CastLevel.Simple.OptVal!CastLevel;

			case ADataType.Type.NoInit:
				if (target.type != ADataType.Type.NoInit)
					break;
				return CastLevel.None.OptVal!CastLevel;

			case ADataType.Type.Struct:
				if (target.type == ADataType.Type.Struct &&
						this.structS == target.structS)
					return CastLevel.None.OptVal!CastLevel;
				if (this.structS is null){
					return OptVal!CastLevel();
				}
				const AStruct* symC = this.structS;
				if (symC.hasBase(ctx))
					return symC.types[symC.names[This][0]].castability(target, ctx);
				return OptVal!CastLevel();

			case ADataType.Type.Union:
				if (target.type == ADataType.Type.Union &&
						this.unionS == target.unionS)
					return CastLevel.None.OptVal!CastLevel;
				return OptVal!CastLevel();

			case ADataType.Type.Enum:
				return this.enumS.type.castability(target, ctx);
		}
		return OptVal!CastLevel();
	}

	/// Returns: whether this is a primitive type
	@property isPrimitive() const {
		switch (type){
			case Type.IntX, Type.UIntX, Type.FloatX, Type.Char, Type.Bool:
				return true;
			case Type.Slice:
				return this == ADataType.ofString;
			default:
				return false;
		}
	}

	/// Returns: ADataType that is this, but const
	ADataType constOf() const pure {
		ADataType ret = this.copy;
		final switch (type){
			case Type.Slice:
			case Type.Array:
				ret.refT.isConst = true;
				ret.type = Type.Slice;
				break;
			case Type.IntX:
			case Type.UIntX:
			case Type.FloatX:
			case Type.Char:
			case Type.Bool:
			case Type.Fn:
			case Type.Ref:
			case Type.NoInit:
				ret.isConst = true;
				break;
			case Type.Struct:
			case Type.Union:
			case Type.Enum:
				debug stderr.writefln!"STUB: constOf(%s) returning as is"(type);
				break;
		}
		return ret;
	}

	/// Returns: true if this can be casted in-place to target
	bool canIPCastTo(const ADataType target,
			IdentU[] ctx = [IdentU.init]) const pure {
		OptVal!CastLevel r = this.castability(target, ctx);
		if (!r.isVal)
			return false;
		return r.val <= CastLevel.InPlace;
	}

	/// Returns: true if this can be casted to target
	bool canCastTo(const ADataType target,
			IdentU[] ctx = [IdentU.init]) const pure {
		return this.castability(target, ctx).isVal;
	}

	/// Returns: initialized instance of this, or nothing if cannot init
	OptVal!(void[]) buildVal() const pure {
		final switch (type){
			case ADataType.Type.IntX:
			case ADataType.Type.UIntX:
				return new void[sizeOf].OptVal!(void[]); // zero
			case ADataType.Type.FloatX:
				switch (this.x){
					static foreach (Type; Floats){
						case Type.sizeof * 8:
							return (cast(Type)0.0).asBytes.OptVal!(void[]);
					}
					default:
						return new void[sizeOf].OptVal!(void[]);
				}
			case ADataType.Type.Char:
				return (cast(void[])['\0']).OptVal!(void[]);
			case ADataType.Type.Bool:
				return (cast(void[])[false]).OptVal!(void[]);
			case ADataType.Type.Slice:
			case ADataType.Type.Array:
				return new void[sizeOf].OptVal!(void[]);
			case ADataType.Type.Ref:
			case ADataType.Type.Fn:
				return OptVal!(void[])();
			case ADataType.Type.Struct:
				if (this.structS is null)
					return [].OptVal!(void[]);
				return this.structS.buildVal;
			case ADataType.Type.Union:
				return this.unionS.buildVal;
			case ADataType.Type.Enum:
				assert (this.enumS.memVal.length);
				return this.enumS.memVal[0].dup.OptVal!(void[]);
			case ADataType.Type.NoInit:
				return OptVal!(void[])();
		}
	}

	string toString() const pure {
		string ret = isConst ? "const " : null;
		final switch (type){
			case Type.IntX:
				return ret ~ x.format!"$int(%d)";
			case Type.UIntX:
				return ret ~ x.format!"$uint(%d)";
			case Type.FloatX:
				return ret ~ x.format!"$float(%d)";
			case Type.Char:
				return ret ~ "$char";
			case Type.Bool:
				return ret ~ "bool";
			case Type.Slice:
				return (*refT).toString.format!"$slice(%s)"; // cannot be const
			case Type.Array:
				return (*refT).toString.format!"$array(%s)"; // cannot be const
			case Type.Fn:
				return format!"fn(%s)->%s"(
						paramT.map!(p => p.toString).join(","), retT.toString);
			case Type.Ref:
				return ret ~ (*refT).toString.format!"@%s";
			case Type.Struct:
				if (structS is null)
					return "struct{}";
				return structS.ident.toString.format!"struct(%s)";
			case Type.Union:
				if (unionS is null)
					return "union{}";
				return unionS.ident.toString.format!"union(%s)";
			case Type.Enum:
				if (enumS is null)
					return "enum{}";
				return enumS.ident.toString.format!"enum(%s)";
			case Type.NoInit:
				return "$noinit";
		}
		assert(false);
	}

	/// Returns: byte size of type
	@property size_t sizeOf() const pure {
		final switch (type){
			case Type.IntX, Type.UIntX, Type.FloatX:
				return x / 8;
			case Type.Char:
			case Type.Bool:
				return 1;
			case Type.Slice:
				return 2 * null.sizeof; // ptr + length
			case Type.Array:
				return 3 * null.sizeof; // ptr + length + capacity
			case Type.Fn:
				return 2 * null.sizeof; // ptr + closurePtr
			case Type.Ref:
				return null.sizeof;
			case Type.Struct:
				if (structS is null)
					return 0;
				return this.structS.sizeOf;
			case Type.Union:
				assert (unionS !is null);
				return unionS.sizeOf;
			case Type.Enum:
				assert(enumS !is null);
				return enumS.type.sizeOf;
			case Type.NoInit:
				return 0;
		}
	}

	ADataType copy() const pure {
		ADataType ret;
		ret.type = type;
		ret.isConst = isConst;
		final switch (type){
			case Type.IntX:
			case Type.UIntX:
			case Type.FloatX:
				ret.x = x;
				break;
			case Type.Char:
			case Type.Bool:
			case Type.NoInit:
				break;
			case Type.Slice:
			case Type.Array:
				ret.refT = [(*refT).copy].ptr;
				break;
			case Type.Ref:
				ret.refT = [(*refT).copy].ptr;
				break;
			case Type.Fn:
				ret.retT = [(*retT).copy].ptr;
				break;
			case Type.Struct:
				ret.structS = cast(AStruct*)structS;
				break;
			case Type.Union:
				ret.unionS = cast(AUnion*)unionS;
				break;
			case Type.Enum:
				ret.enumS = cast(AEnum*)enumS;
		}
		return ret;
	}

	/// Returns: ADataType equivalent of `T`
	static ADataType of(T...)() pure if (T.length && allSatisfy!(isType, T)) {
		static if (T.length == 1){
			static if (std.traits.isNumeric!(T[0])){
				static if (isFloatingPoint!(T[0]))
					return ADataType.ofFloat(T[0].sizeof * 8);
				static if (isUnsigned!(T[0]))
					return ADataType.ofUInt(T[0].sizeof * 8);
				return ADataType.ofInt(T[0].sizeof * 8);
			} else
			static if (is (T[0] == char)){
				return ADataType.ofChar;
			} else
			static if (isBoolean!(T[0])){
				return ADataType.ofBool;
			} else
			static if (isPointer!(T[0])){
				return ADataType.ofRef(ADataType.of!(PointerTarget!(T[0])));
			} else
			static if (is (T[0] == string)){
				return ADataType.ofString;
			} else
			static if (isStaticArray!(T[0])){
				return ADataType.ofSlice(ADataType.of!(ElementType!(T[0])));
			} else
			static if (isArray!(T[0])){
				return ADataType.ofArray(ADataType.of!(ElementType!(T[0])));
			} else
			static if (isFunction!(T[0]) || isFunctionPointer!(T[0])){
				static assert (false, "ADataType.of(T) does not suppport Fn yet");
			} else
			static if (is (T[0] == struct)){
				static assert (false, "ADataType.of(T) does not suppport Struct yet");
			} else
			static if (is (T[0] == union)){
				static assert (false, "ADataType.of(T) does not suppport Union yet");
			} else
			static if (is (T[0] == enum)){
				static assert (false, "ADataType.of(T) does not suppport Enum yet");
			} else {
				static assert (false, "Unsupported data type for ADataType.of(T)");
			}
		} else {
			return ADataType.ofSeq([staticMap!(ADataType.of, T)]);
		}
	}

	/// Returns: `$noinit` data type
	static ADataType ofNoInit() pure {
		ADataType ret;
		ret.type = ADataType.Type.NoInit;
		return ret;
	}

	/// Returns: Integer of X bits type
	static ADataType ofInt(ubyte x = size_t.sizeof * 8) pure {
		ADataType ret;
		ret.type = Type.IntX;
		ret.x = x;
		return ret;
	}

	/// Returns: Unsigned Integer of X bits type
	static ADataType ofUInt(ubyte x = ptrdiff_t.sizeof * 8) pure {
		ADataType ret;
		ret.type = Type.UIntX;
		ret.x = x;
		return ret;
	}

	/// Returns: Float of X bits type
	static ADataType ofFloat(ubyte x = double.sizeof * 8) pure {
		ADataType ret;
		ret.type = Type.FloatX;
		ret.x = x;
		return ret;
	}

	/// Returns: Char of X bits type
	static ADataType ofChar() pure {
		ADataType ret;
		ret.type = Type.Char;
		return ret;
	}

	/// Returns: Bool type
	static ADataType ofBool() pure {
		ADataType ret;
		ret.type = Type.Bool;
		return ret;
	}

	/// Returns: slice type
	static ADataType ofSlice(ADataType elemT) pure {
		ADataType ret;
		ret.type = Type.Slice;
		ret.refT = [elemT].ptr;
		return ret;
	}

	/// Returns: array type
	static ADataType ofArray(ADataType elemT) pure {
		ADataType ret;
		ret.type = Type.Array;
		ret.refT = [elemT].ptr;
		return ret;
	}

	static ADataType ofString() pure {
		ADataType str;
		str.type = Type.Slice;
		str.refT = [ADataType.ofChar.constOf].ptr;
		str.refT.isConst = true;
		return str; // $slice(const char)
	}

	/// Returns: function type
	static ADataType ofFn(ADataType retT, ADataType[] paramT) pure {
		ADataType ret;
		ret.type = Type.Fn;
		ret.retT = [retT].ptr;
		ret.paramT = paramT;
		return ret;
	}

	/// Returns: reference type
	static ADataType ofRef(ADataType refT) pure {
		ADataType ret;
		ret.type = Type.Ref;
		ret.refT = [refT].ptr;
		return ret;
	}

	/// Returns: struct type
	static ADataType of(AStruct* structT) pure {
		ADataType ret;
		ret.type = Type.Struct;
		ret.structS = structT;
		return ret;
	}

	/// Returns: union type
	static ADataType of(AUnion* unionT) pure {
		ADataType ret;
		ret.type = Type.Union;
		ret.unionS = unionT;
		return ret;
	}

	/// Returns: enum type
	static ADataType of(AEnum* enumT) pure {
		ADataType ret;
		ret.type = Type.Enum;
		ret.enumS = enumT;
		return ret;
	}

	bool opEquals()(auto ref const ADataType rhs) const pure {
		if (type != rhs.type)
			return false;
		final switch (type){
			case Type.IntX:
			case Type.UIntX:
			case Type.FloatX:
				return x == rhs.x;
			case Type.Char:
			case Type.Bool:
				return true;
			case Type.Slice:
			case Type.Array:
			case Type.Ref:
				return *refT == *rhs.refT;
			case Type.Fn:
				if (retT != rhs.retT || paramT.length != rhs.paramT.length)
					return false;
				foreach (size_t i; paramT.length.iota){
					if (paramT[i] != rhs.paramT[i])
						return false;
				}
				return true;
			case Type.Struct:
				if (this.structS is null)
					return rhs.structS is null;
				if (rhs.structS is null)
					return false;
				return structS == rhs.structS;
			case Type.Union:
				return unionS !is null && unionS == rhs.unionS;
			case Type.Enum:
				return enumS !is null && enumS == rhs.enumS;
			case Type.NoInit:
				return true;
		}
		return true;
	}
}

/// Alis struct
public struct AStruct{
	/// identifier, `ident.isNoId == true` if anonymous
	IdentU[] ident;
	/// data types for each field
	ADataType[] types;
	/// initialisation data for each field
	OptVal!(void[])[] initD;
	/// maps member names to indexes sequence. Many to One
	size_t[][string] names;
	/// visibility for each name
	Visibility[string] nameVis;
	/// Visibility of struct
	Visibility vis;

	/// if this is unique
	@property bool isUnique() const pure {
		return ident.length && !ident[$ - 1].ident.canFind('$');
	}
	/// Whether a member exists and is accessible
	bool exists(string name, IdentU[] ctx = [IdentU.init]) const pure {
		if (name !in names)
			return false;
		if (!isUnique)
			return true;
		immutable auto len = cast(ptrdiff_t)ident.length - 1;
		if (ctx.length >= len && ident[0 .. len] == ctx[0 .. len])
			return true;
		if (const Visibility* vis = name in nameVis)
			return *vis == Visibility.Pub || *vis == Visibility.IPub;
		return true;
	}
	/// whether the 0th member is aliased to `this`
	@property bool hasBase(IdentU[] ctx = [IdentU.init]) const pure {
		return exists(This, ctx) && names[This].length == 1;
	}
	/// Returns: size of this struct
	@property size_t sizeOf() const pure {
		return types.map!(t => t.sizeOf).sum;
	}

	/// Returns: offset of a member, by member Id. `size_t.max` if out of bounds
	size_t offsetOf(size_t memId) const pure {
		if (memId >= types.length)
			return size_t.max;
		return types[0 .. memId].map!(t => t.sizeOf).sum;
	}

	/// Returns: range of human readable names for a member Id
	auto namesOf(size_t memId, IdentU[] ctx = [IdentU.init]) const pure {
		return names.byKey.filter!(n => exists(n, ctx))
			.map!(n => tuple(n, names[n].countUntil(memId), names[n].length))
			// (0 -> name, 1 -> index, 2 -> ids.length)
			.filter!(n => n[1] >= 0)
			.map!(n => n[2] == 1 ? n[0] : n[0].format!"%s[%d]"(n[1]))
			.chain([memId.format!"<member %d>"]);
	}

	/// Returns: initialized instance of this, or nothing if cannot init
	public OptVal!(void[]) buildVal() const pure {
		foreach (const OptVal!(void[]) fieldInit; initD){
			if (!fieldInit.isVal)
				return OptVal!(void[])();
		}
		void[] ret = new void[sizeOf];
		size_t offset = 0;
		foreach (const OptVal!(void[]) fieldInit; initD){
			ret[offset .. offset + fieldInit.val.length] = fieldInit.val;
			offset += fieldInit.val.length;
		}
		return OptVal!(void[])(ret);
	}

	/// ditto
	public OptVal!(void[]) buildVal(AVal src, IdentU[] ctx) const pure {
		if (src.type.type == ADataType.Type.Struct &&
				src.type.structS is null &&
				this.types.length == 0){
			return OptVal!(void[])([]);
		}
		if (src.type.type == ADataType.Type.Struct &&
				src.type.structS !is null &&
				!src.type.structS.isUnique){
			AStruct* type = src.type.structS;
			bool skip = false;
			size_t[2][size_t] idMap; // index in dst -> [offset in src, index in src]
			size_t[size_t] idRMap; // index in src -> index in dst
			foreach (string name; type.names.byKey
					.filter!(n => type.exists(n, ctx))){
				if (!this.exists(name, ctx)){
					skip = true;
					break;
				}
				const size_t[] srcIds = type.names[name];
				const size_t[] dstIds = this.names[name];
				if (srcIds.length != dstIds.length){
					skip = true;
					break;
				}
				foreach (size_t i; 0 .. dstIds.length){
					size_t srcId = srcIds[i];
					size_t dstId = dstIds[i];
					if (srcId in idMap ||
							!type.types[srcId].canCastTo(this.types[dstId], ctx)){
						skip = true;
						break;
					}
					idMap[dstId] = [size_t.max, srcId];
					idRMap[srcId] = dstId;
				}
			}
			if (!skip){
				size_t offset = 0;
				foreach (size_t i; 0 .. type.types.length){
					if (i in idRMap)
						idMap[idRMap[i]][0] = offset;
					offset += type.types[i].sizeOf;
				}
				void[] ret = new void[sizeOf];
				offset = 0;
				foreach (size_t i; 0 .. this.types.length){
					const ADataType dstType = this.types[i];
					OptVal!(void[]) data = OptVal!(void[])();
					if (size_t[2]* ptr = i in idMap){
						ADataType srcType = type.types[(*ptr)[1]];
						size_t off = (*ptr)[0];
						OptVal!AVal convd = AVal(srcType,
								src.data[off .. off + srcType.sizeOf]).to(dstType, ctx);
						if (!convd.isVal){
							skip = true;
							break;
						}
						data = OptVal!(void[])(convd.val.data);
					}
					if (!data.isVal){
						if (!initD[i].isVal){
							skip = true;
							break;
						}
						data = cast(OptVal!(void[]))initD[i];
					}
					ret[offset .. offset + dstType.sizeOf] = data.val;
				}
				return ret.OptVal!(void[]);
			}
		}

		void[0][size_t] visIds;
		foreach (string name; this.names.byKey.filter!(n => this.exists(n, ctx))){
			foreach (size_t id; this.names[name]){
				visIds[id] = (void[0]).init;
			}
		}
		size_t toInit = size_t.max;
		foreach (size_t id; visIds.byKey){
			if (!src.type.canCastTo(this.types[id], ctx)) continue;
			if (toInit != size_t.max)
				return OptVal!(void[])();
			toInit = id;
		}
		if (toInit == size_t.max)
			return OptVal!(void[])();
		OptVal!AVal convd = src.to(this.types[toInit], ctx);
		if (!convd.isVal)
			return OptVal!(void[])();

		void[] ret = new void[sizeOf];
		size_t offset = 0;
		foreach (size_t i; 0 .. this.types.length){
			size_t size = this.types[i].sizeOf;
			if (i == toInit){
				ret[offset .. offset + size] = convd.val.data;
			} else {
				const OptVal!(void[]) data = initD[i];
				if (!data.isVal)
					return OptVal!(void[])();
				ret[offset .. offset + size] = data.val;
			}
			offset += size;
		}
		return OptVal!(void[])(ret);
	}

	/// Returns: true if this can be initialized from some data type
	public bool canBuildVal(const ADataType srcType, IdentU[] ctx) const pure {
		if (srcType.type == ADataType.Type.Struct &&
				srcType.structS is null &&
				this.types.length == 0){
			return true;
		}
		if (srcType.type == ADataType.Type.Struct &&
				srcType.structS !is null &&
				!srcType.structS.isUnique){
			const(AStruct)* type = srcType.structS;
			bool skip = false;
			size_t[size_t] idMap; // index in dst -> [index in src]
			foreach (string name; type.names.byKey
					.filter!(n => type.exists(n, ctx))){
				if (!this.exists(name, ctx)){
					skip = true;
					break;
				}
				const size_t[] srcIds = type.names[name];
				const size_t[] dstIds = this.names[name];
				if (srcIds.length != dstIds.length){
					skip = true;
					break;
				}
				foreach (size_t i; 0 .. dstIds.length){
					size_t srcId = srcIds[i];
					size_t dstId = dstIds[i];
					if (srcId in idMap ||
							!type.types[srcId].canCastTo(this.types[dstId], ctx)){
						skip = true;
						break;
					}
					idMap[dstId] = srcId;
				}
			}
			if (!skip){
				foreach (size_t i; 0 .. this.types.length){
					const ADataType dstType = this.types[i];
					if (size_t* ptr = i in idMap){
						size_t off = *ptr;
						const ADataType sType = type.types[off];
						if (!sType.canCastTo(dstType, ctx))
							return false;
					}
					if (!initD[i].isVal)
						return false;
				}
				return false;
			}
		}

		void[0][size_t] visIds;
		foreach (string name; this.names.byKey.filter!(n => this.exists(n, ctx))){
			foreach (size_t id; this.names[name]){
				visIds[id] = (void[0]).init;
			}
		}
		size_t toInit = size_t.max;
		foreach (size_t id; visIds.byKey){
			if (!srcType.canCastTo(this.types[id], ctx)) continue;
			if (toInit != size_t.max)
				return false;
			toInit = id;
		}
		if (toInit == size_t.max)
			return false;
		foreach (size_t i; 0 .. this.types.length){
			if (i == toInit) continue;
			if (this.initD.length <= i || !this.initD[i].isVal)
				return false;
		}
		return true;
	}

	string toString() const pure {
		Appender!string ret;
		ret.put("struct ");
		ret.put(ident.toString);
		ret.put("{");
		foreach (size_t id, const ADataType type; this.types){
			foreach (string name, const size_t[] ids; this.names){
				ptrdiff_t index = ids.countUntil(id);
				if (index < 0) continue;
				final switch (nameVis[name]){
					case Visibility.Default:
						break;
					case Visibility.IPub:
						ret.put("ipub ");
						break;
					case Visibility.Pub:
						ret.put("pub ");
						break;
				}
				ret.put(name);
				if (ids.length > 1){
					ret.put("[");
					ret.put(index.to!string);
					ret.put("]");
				}
				ret.put(" ");
			}
			ret.put(": ");
			ret.put(type.toString);
			if (initD[id].isVal){
				ret.put(" = ");
				ret.put(AVal(type, initD[id].val).toString);
			}
			ret.put("; ");
		}
		ret.put("}");
		return ret.data;
	}
}

/// Alis union
public struct AUnion{
	/// identifier
	IdentU[] ident;
	/// types of members
	ADataType[] types;
	/// maps field names to sequence of indexes in `types`.
	/// can be null, if unnamed
	size_t[][string] names;
	/// name's visibility. can be null, if unnamed
	Visibility[string] nameVis;
	/// initialisation type's index, or `size_t.max` if none
	size_t initI = size_t.max;
	/// initialisation data
	OptVal!(void[]) initD;
	/// Visibility outside its parent module
	Visibility vis;

	/// Whether a member exists and is accessible
	bool exists(string name, IdentU[] ctx = [IdentU.init]) const pure {
		if (name !in names)
			return false;
		if (!isUnique)
			return true;
		immutable auto len = cast(ptrdiff_t)ident.length - 1;
		if (ctx.length >= len && ident[0 .. len] == ctx[0 .. len])
			return true;
		if (const Visibility* vis = name in nameVis)
			return *vis == Visibility.Pub || *vis == Visibility.IPub;
		return true;
	}
	/// whether the 0th member is aliased to `this`
	@property bool hasBase(IdentU[] ctx = [IdentU.init]) const pure {
		return exists(This, ctx);
	}
	/// if this is unique
	@property bool isUnique() const pure {
		return ident.length && !ident[$ - 1].ident.canFind('$');
	}
	/// Returns: true if this is an unnamed union
	@property bool isUnnamed() const pure {
		return names.length == 0;
	}
	/// Returns: size of this union excluding memId at end
	@property sizeOfField() const pure {
		return types.map!(t => t.sizeOf).fold!((a, b) => max(a, b));
	}
	/// Returns: size of this union
	@property size_t sizeOf() const pure {
		return sizeOfField + size_t.sizeof;
	}

	/// Returns: range of human readable names for a member Id
	auto namesOf(size_t memId, IdentU[] ctx = [IdentU.init]) const pure {
		return names.byKey.filter!(n => exists(n, ctx))
			.map!(n => tuple(n, names[n].countUntil(memId), names[n].length))
			// (0 -> name, 1 -> index, 2 -> ids.length)
			.filter!(n => n[1] >= 0)
			.map!(n => n[2] == 1 ? n[0] : n[0].format!"%s[%d]"(n[1]))
			.chain([memId.format!"<member %d>"]);
	}

	/// Returns: initialized instance of this, or nothing if cannot init
	OptVal!(void[]) buildVal() const pure {
		if (initI == size_t.max)
			return OptVal!(void[])();
		void[] ret = new void[sizeOf];
		*(cast(size_t*)(ret.ptr + sizeOfField)) = initI;
		return ret.OptVal!(void[]);
	}

	/// ditto
	OptVal!(void[]) buildVal(AVal src, IdentU[] ctx) const pure {
		if (src.type.type == ADataType.Type.Struct &&
				src.type.structS !is null &&
				!src.type.structS.isUnique &&
				src.type.structS.names.length == 1){
			string firstName = src.type.structS.names.byKey.takeOne[0];
			if (exists(firstName, ctx)){
				const size_t[] ids = this.names[firstName];
				if (ids.length == 1){
					size_t id = ids[0];
					const ADataType dstType = this.types[id];
					OptVal!AVal convd = src.to(dstType, ctx);
					if (convd.isVal){
						void[] ret = new void[sizeOf];
						ret[0 .. dstType.sizeOf] = convd.val.data;
						*(cast(size_t*)(ret.ptr + sizeOfField)) = id;
						return ret.OptVal!(void[]);
					}
				}
			}
		}

		if (names is null || names.length == 0){
			size_t tInd = size_t.max;
			foreach (size_t i, const(ADataType) type; types){
				if (src.canCastTo(type, ctx)){
					if (tInd != size_t.max)
						return OptVal!(void[])();
					tInd = i;
				}
			}
			if (tInd == size_t.max)
				return OptVal!(void[])();
			OptVal!AVal convd = src.to(types[tInd], ctx);
			if (!convd.isVal)
				return OptVal!(void[])();
			void[] ret = new void[sizeOf];
			ret[0 .. types[tInd].sizeOf] = convd.val.data;
			*(cast(size_t*)(ret.ptr + sizeOfField)) = tInd;
			return ret.OptVal!(void[]);
		}

		void[0][size_t] visIds;
		foreach (string name; this.names.byKey.filter!(n => this.exists(n, ctx))){
			foreach (size_t id; this.names[name]){
				visIds[id] = (void[0]).init;
			}
		}
		size_t toInit = size_t.max;
		foreach (size_t id; visIds.byKey){
			if (!src.type.canCastTo(this.types[id], ctx)) continue;
			if (toInit != size_t.max)
				return OptVal!(void[])();
			toInit = id;
		}
		if (toInit == size_t.max)
			return OptVal!(void[])();
		const ADataType dstType = this.types[toInit];
		OptVal!AVal convd = src.to(dstType, ctx);
		if (!convd.isVal)
			return OptVal!(void[])();
		void[] ret = new void[sizeOf];
		ret[0 .. dstType.sizeOf] = convd.val.data;
		*(cast(size_t*)(ret.ptr + sizeOfField)) = toInit;
		return ret.OptVal!(void[]);
	}

	/// Returns: true if this can be initialized from some data type
	bool canBuildVal(const ADataType srcType, IdentU[] ctx) const pure {
		if (srcType.type == ADataType.Type.Struct &&
				srcType.structS !is null &&
				!srcType.structS.isUnique &&
				srcType.structS.names.length == 1){
			string firstName = srcType.structS.names.byKey.takeOne[0];
			if (exists(firstName, ctx)){
				const size_t[] ids = this.names[firstName];
				if (ids.length == 1){
					if (srcType.canCastTo(types[ids[0]], ctx))
						return true;
				}
			}
		}

		if (names is null || names.length == 0){
			size_t tInd = size_t.max;
			foreach (size_t i, const(ADataType) type; types){
				if (srcType.canCastTo(type, ctx)){
					if (tInd != size_t.max)
						return false;
					tInd = i;
				}
			}
			if (tInd == size_t.max)
				return false;
			return srcType.canCastTo(types[tInd], ctx);
		}

		void[0][size_t] visIds;
		foreach (string name; this.names.byKey.filter!(n => this.exists(n, ctx))){
			foreach (size_t id; this.names[name]){
				visIds[id] = (void[0]).init;
			}
		}
		size_t toInit = size_t.max;
		foreach (size_t id; visIds.byKey){
			if (!srcType.canCastTo(this.types[id], ctx)) continue;
			if (toInit != size_t.max)
				return false;
			toInit = id;
		}
		if (toInit == size_t.max)
			return false;
		return srcType.canCastTo(types[toInit], ctx);
	}

	string toString() const pure {
		Appender!string ret;
		ret.put("union ");
		ret.put(ident.toString);
		ret.put("{");
		foreach (size_t id; 0 .. this.types.length){
			foreach (string name, const size_t[] ids; this.names){
				ptrdiff_t index = ids.countUntil(id);
				if (index < 0) continue;
				final switch (nameVis[name]){
					case Visibility.Default:
						break;
					case Visibility.IPub:
						ret.put("ipub ");
						break;
					case Visibility.Pub:
						ret.put("pub ");
						break;
				}
				ret.put(name);
				if (ids.length > 1){
					ret.put("[");
					ret.put(index.to!string);
					ret.put("]");
				}
				ret.put(" ");
			}
			ret.put(": ");
			ret.put(this.types[id].toString);
			if (initI == id){
				ret.put(" = ");
				ret.put(AVal(types[id], initD.val).toString);
			}
			ret.put("; ");
		}
		ret.put("}");
		return ret.data;
	}
}

/// Alis Enum
public struct AEnum{
	/// identifier
	IdentU[] ident;
	/// Data Type. This will be `struct{}` in case of empty emum
	ADataType type;
	/// member identifiers
	string[] memId;
	/// member values
	void[][] memVal;
	/// Visibility outside its parent module
	Visibility vis;

	string toString() const pure {
		return format!"enum %s:%s{%-(%s,%)}"(ident.toString, type,
				memId.length.iota
				.map!(i => format!"%s=%s"(memId[i], AVal(type, memVal[i]).toString))
				);
	}
}

/// Alis Enum Constant
public struct AEnumConst{
	/// identifier
	IdentU[] ident;
	/// type
	ADataType type;
	/// value bytes
	void[] data;
	/// Visibility outside its parent module
	Visibility vis;

	string toString() const pure {
		return format!"enum %s:%s=%s"(ident.toString, type,
				AVal(type, data).toString);
	}
}

/// Alis Function Information
public struct AFn{
	/// identifier, `_` if anonymous
	IdentU[] ident;
	/// return type
	ADataType retT;
	/// parameter names
	string[] paramsN;
	/// parameter types
	ADataType[] paramsT;
	/// parameter default values, if any
	OptVal!(void[])[] paramsV;
	/// unique id. this is also the label name in ABC
	string uid;
	/// whether this is an alis function (true) or an external (false)
	bool isAlisFn = true;
	/// Visibility outside its parent module
	Visibility vis;

	string toString() const pure {
		return format!
			"fn %s%s[%s](%-(%s,%))->%s"(
					(isAlisFn ? "" : "external "),
					ident.toString, uid,
					paramsN.length.iota
					.map!(i => format!"%s:%s%s"(paramsN[i], paramsT[i].toString,
							paramsV[i].isVal
							? AVal(paramsT[i], paramsV[i].val).toString.format!"=%s"
							: "")),
					retT);
	}
}

/// Alis Variable
public struct AVar{
	/// identifier
	IdentU[] ident;
	/// data type
	ADataType type;
	/// initialisation data
	OptVal!(void[]) initD;
	/// Visibility outside its parent module
	Visibility vis;
	/// unique id
	string uid;

	string toString() const pure {
		return format!"var %s[%s]:%s%s"(
				ident.toString, uid, type.toString,
				initD.isVal ? AVal(type, initD.val).toString.format!"=%s" : "");
	}
}

/// Alis Alias
public struct AAlias{
	/// identifier
	IdentU[] ident;
	/// Visibility outside its parent module
	Visibility vis;
	/// expr being aliased
	RExpr expr;

	string toString() const pure {
		return format!"alias %s=%s"(ident, expr is null ? null : expr.toString);
	}
}

/// Alis Import
public struct AImport{
	/// module being imported
	string[] modIdent;
	/// aliased name, if any
	IdentU[] ident;
	/// Visibility outside its parent module
	Visibility vis;

	string toString() const pure {
		return format!"import %s as %s"(modIdent, ident.toString);
	}
}

/// Alis Template
public struct ATemplate{
	/// identifier
	IdentU[] ident;
	/// Visibility outside its parent module
	Visibility vis;
	// TODO: what to store in ATemplate

	string toString() const pure {
		return format!"template";
	}
}

/// Alis Unit Test
public struct AUTest{
	/// identifier
	IdentU[] ident;
	/// Visibility (always default)
	@property Visibility vis(Visibility) const pure { return Visibility.Default; }
	/// ditto
	@property Visibility vis() const pure { return Visibility.Default; }
	/// unique id. this is also the label name in ABC
	string uid;

	string toString() const pure {
		return format!"utest %s[%s]"(ident, uid);
	}
}

/// Encodes function name, using function name and param types
/// Returns: encoded name
public string fnNameEncode(string name, ADataType[] args){
	return format!"%s$%(_%r%)_$"(name, args.map!(a => a.toString));
}

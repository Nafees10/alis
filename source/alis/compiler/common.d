/++
Common compiler components
+/
module alis.compiler.common;

import std.conv,
			 std.json,
			 std.format;

/// parent to all nodes
public abstract class ASTNode{
public:
	/// location in source code
	Location pos;
	/// returns: JSON representation
	JSONValue jsonOf() const pure {
		JSONValue ret;
		ret["location.line"] = JSONValue(pos.line);
		ret["location.col"] = JSONValue(pos.col);
		ret["_name"] = "ASTNode";
		return ret;
	}

	override string toString() const {
		return jsonOf.toPrettyString;
	}
}

/// Whether a class is inherited from `ASTNode`
public enum IsASTNode(T) = is (T : ASTNode);

/// Intrinsic Names (excluding leading `$`)
public enum IntrN : string{
	// types
	Type = "type",
	NoInit = "noinit",
	NoInitVal = "noinitval",
	Init = "init",
	Int = "int",
	UInt = "uint",
	Float = "float",
	Char = "char",
	Slice = "slice",
	Array = "array",
	IsType = "isType",
	TypeOf = "typeOf",

	// ararys & sequences
	ArrayLen = "arrLen",
	ArrayInd = "arrInd",
	SeqLen = "seqLen",
	SeqInd = "seqInd",

	// unions & aggregates
	UnionIs = "unionIs",
	MembersCount = "membersCount",
	MemberNames = "memberNames",
	MemberIds = "memberIds",
	Member = "member",

	// attributes
	AttrsOf = "attrsOf",
	ByAttrs = "byAttrs",

	// misc
	Debug = "debug",
	StackTrace = "stackTrace",
	Err = "err",

	// printing
	RTWrite = "rtWrite",
	CTWrite = "ctWrite",

	// arithmetic operations
	Negate = "negate",
	BitNot = "bitNot",
	BitOr = "bitOr",
	BitAnd = "bitAnd",
	BitXor = "bitXor",
	Add = "add",
	Sub = "sub",
	Mul = "mul",
	Div = "div",
	Mod = "mod",
	ShiftL = "shiftL",
	ShiftR = "shiftR",

	// comparison
	Is = "is",
	IsNot = "isNot",
	IsLess = "isLess",
	Not = "not",

	// casting
	To = "to"
}

/// Returns: true if a string is a valid intrinsic name
public bool isIntrN(string s) pure {
	import std.traits : EnumMembers;
	switch (s){
		static foreach (Member; EnumMembers!IntrN){
			case Member:
		}
		return true;
	default:
		return false;
	}
	return false; // just in case
}
///
unittest{
	assert ("type".isIntrN);
	assert ("to".isIntrN);
	assert ("foo".isIntrN == false);
	assert ("bar".isIntrN == false);
}

/// ASTNode location
public struct Location{
	size_t line;
	size_t col;
	string toString() const pure {
		return format!"%d,%d"(line, col);
	}
}

/// A possibly erroneous value.
public struct ErrVal(T, E){
	private bool _isErr;
	private union{
		T _val;
		E _err;
	}

	/// Returns: true if this is erroneous
	public @property bool isErr() const pure {
		return _isErr;
	}
	/// Returns: error
	public @property E err() pure {
		assert (isErr);
		return _err;
	}
	/// Returns: value
	public @property T val() pure {
		assert (!isErr);
		return _val;
	}

	/// constructor
	this(E err) pure {
		this._isErr = true;
		this._err = err;
	}
	/// ditto
	this(T val) pure {
		this._isErr = false;
		this._val = val;
	}
}

/// An optional value
public struct OptVal(T){
	private bool _isVal = false;
	private union{
		T _val;
		void[0] _none = (void[0]).init;
	}

	/// Returns: true if this value exists
	public @property bool isVal() const pure {
		return _isVal;
	}
	/// Returns: value
	public @property T val() pure {
		assert (_isVal);
		return _val;
	}
	/// ditto
	public @property const(T) val() const pure {
		assert(_isVal);
		return _val;
	}

	/// constructor
	this(T val) pure {
		this._isVal = true;
		this._val = val;
	}
}

/// unescapes a string. the string must be provided with surrounding quotes
/// stripped
///
/// Returns: unescaped string
package char[] strUnescape(string str){
	uint i, shift;
	char[] r;
	r.length = str.length;
	while (i + shift < str.length && i < r.length){
		if (str[i + shift] == '\\'){
			shift ++;
			if (i + shift < str.length){
				r[i] = charUnescape(str[i + shift]);
				r.length --;
			}
		} else
			r[i] = str[i + shift];
		i ++;
	}
	return r;
}
///
unittest{
	string s = "t\\\"bcd\\\"\\t\\\\";
	assert(strUnescape(s) == "t\"bcd\"\t\\", strUnescape(s));
}

/// Returns: unescaped character, for a character `c` when used as `\c`
package char charUnescape(char c){
	switch (c){
		case 't':	return '\t';
		case 'n':	return '\n';
		case 'b':	return '\b';
		default:	return c;
	}
}

/// Reads a void[] as a type
/// Returns: value in type T
pragma(inline, true) package inout(T) as(T)(inout void[] data) {
	assert(data.length >= T.sizeof);
	return *(cast(T*)data.ptr);
}

/// Returns: void[] against a value of type T
pragma(inline, true) package inout(void[]) asBytes(T)(inout T val) {
	void[] ret;
	ret.length = T.sizeof;
	return ret[] = (cast(void*)&val)[0 .. T.sizeof];
}

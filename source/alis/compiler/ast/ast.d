/++
AST Node definitions package
+/
module alis.compiler.ast.ast;

import std.array,
			 std.json,
			 std.conv,
			 std.algorithm;

import alis.common;
import alis.compiler.common : ASTNode, IsASTNode;

import std.meta,
			 std.traits;

private template GetAll(){
	alias GetAll = AliasSeq!();
	static foreach (string name; __traits(allMembers, mixin(__MODULE__))){
		static if (is (__traits(getMember, mixin(__MODULE__), name) : ASTNode)){
			GetAll = AliasSeq!(GetAll, __traits(getMember, mixin(__MODULE__), name));
		}
	}
}

/// Sequence of all ASTNodes in this module
public alias ASTNodes = GetAll!();

/// alis module
public class Module : ASTNode{
public:
	/// module identifier (can have dots)
	string ident;
	/// definitions
	GlobDef[] defs;
	/// conditional compilation
	CCNode[] cComp;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["defs"] = defs.map!(a => a.jsonOf).array;
		ret["cComp"] = cComp.map!(a => a.jsonOf).array;
		ret["_name"] = "Module";
		return ret;
	}
}

// Misc -----------------------------------------------------------------------

/// Key Value pair node (keyIdent = valExpr)
public class KeyVal : ASTNode{
public:
	/// key ident
	string key;
	/// value
	Expression val;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["key"] = key;
		if (val)
			ret["val"] = val.jsonOf;
		ret["_name"] = "KeyVal";
		return ret;
	}
}

/// Mixin Init
public class MixinInit : ASTNode{
public:
	/// Mixin
	Expression mixn;
	/// Parameters
	Expression[] params;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["mixn"] = mixn.jsonOf;
		ret["params"] = params.map!(a => a.jsonOf).array;
		ret["_name"] = "MixinInit";
		return ret;
	}
}

/// Mixin init to definition
public class MixinInitDef : DefNode{
public:
	/// underlying mixinInit
	MixinInit mixinInit;
	this(){
		name = "_";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["mixinInit"] = mixinInit.jsonOf;
		ret["_name"] = "MixinInitDef";
		return ret;
	}
}

/// Attribute List
public class AttrList : ASTNode{
public:
	/// attributes
	Expression[] attrs;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		if (attrs)
			ret["attrs"] = attrs.map!(a => a.jsonOf).array;
		ret["_name"] = "AttrList";
		return ret;
	}
}

/// Any Block (body is just tokens)
public class AnyBlock : ASTNode{
public:
	import alis.compiler.lexer : Tok;
	Tok[] body;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["body"] = body.map!(a => a.toString).array;
		ret["_name"] = "AnyBlock";
		return ret;
	}
}

/// Aggregate Member List
public class AggMemberList : ASTNode{
public:
	/// aggregate members
	AggMember[] members;
	/// unnamed members
	UnnamedUnionMember[] uMembers;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		if (members)
			ret["members"] = members.map!(a => a.jsonOf).array;
		if (uMembers)
			ret["uMembers"] = uMembers.map!(a => a.jsonOf).array;
		ret["_name"] = "AggMemberList";
		return ret;
	}
}

/// aggregate member (union/struct member)
public abstract class AggMember : ASTNode{
public:
	/// visibility
	Visibility visibility;
	/// attributes
	AttrList attrs;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["visibility"] = visibility.to!string;
		if (attrs)
			ret["attrs"] = attrs.jsonOf;
		ret["_name"] = "AggMember";

		return ret;
	}
}

/// AggMember in case of alias
public class AggMemberAlias : AggMember{
public:
	/// name
	string name;
	/// val
	IdentExpr val;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["name"] = name;
		ret["val"] = val.jsonOf;
		ret["_name"] = "AggMemberAlias";
		return ret;
	}
}

/// AggMember named
public class AggMemberNamed : AggMember{
public:
	/// type
	Expression type;
	/// name
	string name;
	/// default value, can be null
	Expression val;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["type"] = type.jsonOf;
		ret["name"] = name;
		if (val)
			ret["val"] = val.jsonOf;
		ret["_name"] = "AggMemberNamed";
		return ret;
	}
}

/// AggMember unnamed
public class UnnamedUnionMember : ASTNode{
public:
	/// attributes
	AttrList attrs;
	/// type
	Expression type;
	/// default value, can be null
	Expression val;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["type"] = type.jsonOf;
		if (val)
			ret["val"] = val.jsonOf;
		if (attrs)
			ret["attrs"] = attrs.jsonOf;
		ret["_name"] = "UnnamedUnionMember";
		return ret;
	}
}

// Definitions ----------------------------------------------------------------

/// definition node
public abstract class DefNode : ASTNode{
public:
	/// attributes
	AttrList attrs;
	/// name
	string name;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		if (attrs)
			ret["attrs"] = attrs.jsonOf;
		ret["name"] = name;
		ret["_name"] = "DefNode";
		return ret;
	}
}

/// global (module level) definition node
public class GlobDef : ASTNode{
public:
	/// visibility
	Visibility visibility = Visibility.Default;
	/// definition node
	DefNode def;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["def"] = def.jsonOf;
		ret["_name"] = "GlobDef";
		ret["visibility"] = visibility.to!string;
		return ret;
	}
}

/// import
public class Import : DefNode{
public:
	/// module identifier (dot separated strings)
	string[] moduleIdent;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["moduleIdent"] = moduleIdent;
		ret["_name"] = "Import";
		return ret;
	}
}

/// function paramter node
public class FParam : ASTNode{
public:
	/// attributes
	AttrList attrs;
	/// name
	string name;
	/// type, can be null
	Expression type;
	/// default value, can be null
	Expression val;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		if (name)
			ret["name"] = name;
		if (type)
			ret["type"] = type.jsonOf;
		if (val)
			ret["val"] = val.jsonOf;
		ret["_name"] = "FParam";
		return ret;
	}
}

/// function parameter list
public class FParamList : ASTNode{
public:
	/// parameterse
	FParam[] params;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["params"] = params.map!(a => a.jsonOf).array;
		ret["_name"] = "FParamList";
		return ret;
	}
}

/// function definition
public class FnDef : DefNode{
public:
	/// parameters
	FParamList params;
	/// template paramters, can be null
	TParamList tParams;
	/// body expression
	Expression body;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["params"] = params.jsonOf;
		if (tParams)
			ret["tParams"] = tParams.jsonOf;
		ret["body"] = body.jsonOf;
		ret["_name"] = "FnDef";
		return ret;
	}
}

/// abstract enum
public abstract class EnumDef : DefNode{
public:
	/// type
	Expression type;
	/// template paramters, can be null
	TParamList tParams;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["type"] = type.jsonOf;
		if (tParams)
			ret["tParams"] = tParams.jsonOf;
		ret["_name"] = "EnumDef";
		return ret;
	}
}

/// enum constant definition
public class EnumConstDef : EnumDef{
public:
	/// value
	Expression val;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["val"] = val.jsonOf;
		ret["_name"] = "EnumConstDef";
		return ret;
	}
}

/// enum definition
public class EnumSmDef : EnumDef{
public:
	/// members
	EnumMember[] members;
	/// mixin inits
	MixinInit[] mixinInits;
	/// conditional compilation
	CCNode[] cComp;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["members"] = members.map!(a => a.jsonOf).array;
		ret["mixinInits"] = mixinInits.map!(a => a.jsonOf).array;
		ret["cComp"] = cComp.map!(a => a.jsonOf).array;
		ret["_name"] = "EnumSmDef";
		return ret;
	}
}

/// enum member
public class EnumMember : ASTNode{
public:
	/// attributes
	AttrList attrs;
	/// name
	string name;
	/// value. can be null
	Expression value;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		if (value)
			ret["value"] = value.jsonOf;
		ret["_name"] = "EnumMember";
		return ret;
	}
}

/// A struct
public class Struct : ASTNode{
public:
	/// members
	AggMember[] members;
	/// conditional compilation
	CCNode[] cComp;
	/// Mixin Inits
	MixinInit[] mixinInits;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["members"] = members.map!(a => a.jsonOf).array;
		ret["mixinInits"] = mixinInits.map!(a => a.jsonOf).array;
		ret["cComp"] = cComp.map!(a => a.jsonOf).array;
		ret["_name"] = "Struct";
		return ret;
	}
}

/// struct definition
public class StructDef : DefNode{
public:
	/// underlying struct
	Struct def;
	/// template paramters, can be null
	TParamList tParams;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["def"] = def.jsonOf;
		if (tParams)
			ret["tParams"] = tParams.jsonOf;
		ret["_name"] = "StructDef";
		return ret;
	}
}

/// abstract template parameter node
public abstract class TParam : ASTNode{
public:
	/// attributes
	AttrList attrs;
	/// name
	string name;
	/// specialization
	Expression[] specialization;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["specialization"] = specialization.map!(a => a.jsonOf).array;
		ret["_name"] = "TParam";
		return ret;
	}
}

/// template alias paramter node
public class TParamAlias : TParam{
public:
	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "TParamAlias";
		return ret;
	}
}

/// template alias sequence parameter node
public class TParamAliasSeq : TParamAlias{
public:
	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "TParamAliasSeq";
		return ret;
	}
}

/// template $type paramter node
public class TParamType : TParam{
public:
	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "TParamType";
		return ret;
	}
}

/// template $type sequence parameter node
public class TParamTypeSeq : TParamType{
public:
	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "TParamTypeSeq";
		return ret;
	}
}

/// template parameter, typical
public class TParamSm : TParam{
public:
	/// type
	Expression type;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["type"] = type.jsonOf;
		ret["_name"] = "TParamSm";
		return ret;
	}
}

/// template param list
public class TParamList : ASTNode{
public:
	/// parameters
	TParam[] params;
	/// condition, can be null
	Expression condition;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["params"] = params.map!(a => a.jsonOf).array;
		if (condition)
			ret["condition"] = condition.jsonOf;
		ret["_name"] = "TParamList";
		return ret;
	}
}

/// template definition
public class TemplateDef : DefNode{
public:
	/// template paramters, can be null
	TParamList tParams;
	/// body
	AnyBlock body;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		if (tParams)
			ret["tParams"] = tParams.jsonOf;
		ret["body"] = body.jsonOf;
		ret["_name"] = "TemplateDef";
		return ret;
	}
}

/// Mixin Definition
public class TemplateMixinDef : TemplateDef{
public:
	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "TemplateMixinDef";
		return ret;
	}
}

/// variable definition
public class VarDef : DefNode{
public:
	/// type
	Expression type;
	/// optional default value, can be null
	Expression value;
	/// if this is read-only outside parent module
	bool isRO;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["type"] = type.jsonOf;
		if (value)
			ret["value"] = value.jsonOf;
		if (isRO)
			ret["ipub"] = true;
		ret["_name"] = "VarDef";
		return ret;
	}
}

/// static variable definition
public class VarStaticDef : VarDef{
public:
	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "VarStaticDef";
		return ret;
	}
}

/// Variable Definition List
public class VarDefList : DefNode{
public:
	/// defs
	VarDef[] defs;
	this(){
		name = "_";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "VarDefList";
		ret["defs"] = defs.map!(a => a.jsonOf).array;
		return ret;
	}
}

/// alias definition
public class AliasDef : DefNode{
public:
	/// template paramters, can be null
	TParamList tParams;
	/// value
	Expression val;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		if (tParams)
			ret["tParams"] = tParams.jsonOf;
		ret["val"] = val.jsonOf;
		ret["_name"] = "AliasDef";
		return ret;
	}
}

/// An union
public abstract class Union : ASTNode{
public:
	/// conditional compilation
	CCNode[] cComp;
	/// mixin inits
	MixinInit[] mixinInits;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["cComp"] = cComp.map!(a => a.jsonOf).array;
		ret["mixinInits"] = mixinInits.map!(a => a.jsonOf).array;
		ret["_name"] = "Union";
		return ret;
	}
}

/// Unknown union (dont know if named or unnamed). Has zero aggMembers, outside
// of CCNode and MixinInit
public class UnkUnion : Union{
public:
	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "UnkUnion";
		return ret;
	}
}

/// Named Union
public class NamedUnion : Union{
public:
	/// members
	AggMember[] members;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["members"] = members.map!(a => a.jsonOf).array;
		ret["_name"] = "NamedUnion";
		return ret;
	}
}

/// Unnamed Union
public class UnnamedUnion : Union{
public:
	/// member data types
	UnnamedUnionMember[] members;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		if (members)
			ret["members"] = members.map!(a => a.jsonOf).array;
		ret["_name"] = "UnnamedUnion";
		return ret;
	}
}

/// union definition
public class UnionDef : DefNode{
public:
	/// template paramters, can be null
	TParamList tParams;
	/// underlying union
	Union def;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["def"] = def.jsonOf;
		if (tParams)
			ret["tParams"] = tParams.jsonOf;
		ret["_name"] = "UnionDef";
		return ret;
	}
}

/// utest node
public class UTest : DefNode{
public:
	/// test description
	string desc;
	/// test body
	Block body;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		if (desc)
			ret["desc"] = desc;
		ret["body"] = body.jsonOf;
		ret["_name"] = "UTest";
		return ret;
	}
}

// Conditional Compilation ----------------------------------------------------

/// conditional compilation node
public abstract class CCNode : Statement{
public:
}

/// static if statement node
public class StaticIf : CCNode{
public:
	/// conditions
	Expression[] conditions;
	/// on true body, for each condition in conditions
	AnyBlock[] onTrue;
	/// else body, can be null
	AnyBlock onFalse;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["condition"] = conditions.map!(a => a.jsonOf).array;
		ret["onTrue"] = onTrue.map!(a => a.jsonOf).array;
		if (onFalse)
			ret["onFalse"] = onFalse.jsonOf;
		ret["_name"] = "StaticIf";
		return ret;
	}
}

/// static for statement node
public class StaticFor : CCNode{
public:
	/// counter name, can be null
	string countIdent; // TODO store VarDef instead
	/// value type
	Expression valType;
	/// value
	string valIdent; // TODO store VarDef instead
	/// range
	Expression range;
	/// loop body
	AnyBlock body;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["countIdent"] = countIdent;
		ret["valType"] = valType.jsonOf;
		ret["valIdent"] = valIdent;
		ret["range"] = range.jsonOf;
		ret["body"] = body.jsonOf;
		ret["_name"] = "StaticFor";
		return ret;
	}
}

/// Static Case statement
public class StaticCase : ASTNode{
public:
	/// case value
	Expression val;
	/// case block
	AnyBlock body;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["val"] = val.jsonOf;
		ret["body"] = body.jsonOf;
		ret["_name"] = "StaticCase";
		return ret;
	}
}

/// switch case statement
public class StaticSwitch : CCNode{
public:
	/// value to switch on
	Expression val;
	/// cases
	StaticCase[] cases;
	/// conditional compilation
	CCNode[] cComp;
	/// mixin inits
	MixinInit[] mixinInits;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["val"] = val.jsonOf;
		ret["cases"] = cases.map!(a => a.jsonOf).array;
		ret["cComp"] = cComp.map!(a => a.jsonOf).array;
		ret["mixinInits"] = mixinInits.map!(a => a.jsonOf).array;
		ret["_name"] = "StaticSwitch";
		return ret;
	}
}

/// Static Default Case statement
public class StaticCaseDef : StaticCase{
public:
	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "StaticCaseDef";
		return ret;
	}
}

// Statements -----------------------------------------------------------------

/// statement node
public abstract class Statement : ASTNode{
public:
}

/// Mixin init to definition
public class MixinInitStmnt : Statement{
public:
	/// underlying mixinInit
	MixinInit mixinInit;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["mixinInit"] = mixinInit.jsonOf;
		ret["_name"] = "MixinInitStmnt";
		return ret;
	}
}

/// Definition as Statement
public class DefStatement : Statement{
public:
	/// definition
	DefNode def;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "DefStatement";
		ret["def"] = def.jsonOf;
		return ret;
	}
}

/// statement block node
public class Block : Statement{
public:
	/// statements
	Statement[] statements;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["statements"] = statements.map!(a => a.jsonOf).array;
		ret["_name"] = "Block";
		return ret;
	}
}

/// return statemment
public class Return : Statement{
public:
	/// return value, can be null
	Expression val;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		if (val)
			ret["val"] = val.jsonOf;
		ret["_name"] = "Return";
		return ret;
	}
}

/// if statement node
public class If : Statement{
public:
	/// condition
	Expression condition;
	/// on true statement
	Statement onTrue;
	/// on false statement (else), can be null
	Statement onFalse;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["condition"] = condition.jsonOf;
		ret["onTrue"] = onTrue.jsonOf;
		if (onFalse)
			ret["onFalse"] = onFalse.jsonOf;
		ret["_name"] = "If";
		return ret;
	}
}

/// for statement node
public class For : Statement{
public:
	/// counter name, can be null
	string countIdent;
	/// value type
	Expression valType;
	/// value
	string valIdent;
	/// range
	Expression range;
	/// loop body
	Statement body;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["countIdent"] = countIdent;
		ret["valType"] = valType.jsonOf;
		ret["valIdent"] = valIdent;
		ret["range"] = range.jsonOf;
		ret["body"] = body.jsonOf;
		ret["_name"] = "For";
		return ret;
	}
}

/// while statement node
public class While : Statement{
public:
	/// condition
	Expression condition;
	/// loop body
	Statement body;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["condition"] = condition.jsonOf;
		ret["body"] = body.jsonOf;
		ret["_name"] = "While";
		return ret;
	}
}

/// do while statement node
public class DoWhile : Statement{
public:
	/// condition
	Expression condition;
	/// loop body
	Statement body;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["condition"] = condition.jsonOf;
		ret["body"] = body.jsonOf;
		ret["_name"] = "DoWhile";
		return ret;
	}
}

/// Case statement
public class Case : ASTNode{
public:
	/// case value
	Expression val;
	/// case block
	Statement body;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["val"] = val.jsonOf;
		ret["body"] = body.jsonOf;
		ret["_name"] = "Case";
		return ret;
	}
}

/// Default Case statement
public class CaseDef : Case{
public:
	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "CaseDef";
		return ret;
	}
}

/// switch case statement
public class Switch : Statement{
public:
	/// value to switch on
	Expression val;
	/// cases
	Case[] cases;
	/// conditional compilation
	CCNode[] cComp;
	/// mixin inits
	MixinInit[] mixinInits;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["val"] = val.jsonOf;
		ret["cases"] = cases.map!(a => a.jsonOf).array;
		ret["cComp"] = cComp.map!(a => a.jsonOf).array;
		ret["mixinInits"] = mixinInits.map!(a => a.jsonOf).array;
		ret["_name"] = "Switch";
		return ret;
	}
}

// Expressions ----------------------------------------------------------------

/// expression
public abstract class Expression : Statement{
}

/// Idenfifier Expression
public class IdentExpr : Expression{
public:
	/// identifier
	string ident;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["ident"] = ident;
		ret["_name"] = "IdentExpr";
		return ret;
	}
}

/// block expression
public class BlockExpr : Expression{
public:
	/// return type
	Expression type;
	/// block
	Block block;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["type"] = type.jsonOf;
		ret["block"] = block.jsonOf;
		ret["_name"] = "BlockExpr";
		return ret;
	}
}

/// intrinsic expression
public class IntrinsicExpr : Expression{
public:
	/// intrinsic name
	string name;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["name"] = name;
		ret["_name"] = "IntrinsicExpr";
		return ret;
	}
}

/// comma separated expressions
public class CommaExpr : Expression{
public:
	/// expressions
	Expression[] exprs;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["exprs"] = exprs.map!(a => a.jsonOf).array;
		ret["_name"] = "CommaExpr";
		return ret;
	}
}

// Expressions / AnonDefs -----------------------------------------------------

/// struct type expression
public class StructAnon : Expression{
public:
	/// underlying struct
	Struct val;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["val"] = val.jsonOf;
		ret["_name"] = "StructAnon";
		return ret;
	}
}

/// anonymous union
public class UnionAnon : Expression{
public:
	/// underlying union
	Union val;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["val"] = val.jsonOf;
		ret["_name"] = "UnionAnon";
		return ret;
	}
}

/// anonymous function expression
public class FnAnonExpr : Expression{
public:
	/// parameters
	FParamList params;
	/// body
	Expression body;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["params"] = params.jsonOf;
		ret["body"] = body.jsonOf;
		ret["_name"] = "FnAnonExpr";
		return ret;
	}
}

// Expressions / Literals -----------------------------------------------------

/// struct literal expression
public class StructLiteralExpr : Expression{
public:
	/// key value pairs of members
	KeyVal[] keyVals;
	/// conditional compilation
	CCNode[] cComp;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["keyVals"] = keyVals.map!(a => a.jsonOf).array;
		ret["cComp"] = cComp.map!(a => a.jsonOf).array;
		ret["_name"] = "StructLiteralExpr";
		return ret;
	}
}

/// boolean literal expression
public class BoolLiteralExpr : Expression{
public:
	/// value
	bool val;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["val"] = val;
		ret["_name"] = "BoolLiteralExpr";
		return ret;
	}
}

/// literal integer expression
public class LiteralIntExpr : Expression{
public:
	/// value
	ptrdiff_t val;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["val"] = val;
		ret["_name"] = "LiteralIntExpr";
		return ret;
	}
}

/// literal float expression
public class LiteralFloatExpr : Expression{
public:
	/// value
	double val;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["val"] = val;
		ret["_name"] = "LiteralFloatExpr";
		return ret;
	}
}

/// literal string expression
public class LiteralStringExpr : Expression{
public:
	/// value
	string val;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["val"] = val;
		ret["_name"] = "LiteralStringExpr";
		return ret;
	}
}

/// literal character expression
public class LiteralCharExpr : Expression{
public:
	/// value
	char val;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["val"] = val;
		ret["_name"] = "LiteralCharExpr";
		return ret;
	}
}

/// literal array expression
public class LiteralArrayExpr : Expression{
public:
	/// elements
	Expression[] elements;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["elements"] = elements.map!(a => a.jsonOf).array;
		ret["_name"] = "LiteralArrayExpr";
		return ret;
	}
}

// Expressions / Idents -------------------------------------------------------

/// `auto`
public class AutoExpr : IdentExpr{
public:
	/// whether this is a `const auto`
	bool isConst = false;
	this(){
		this.ident = "auto";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["ident"] = ident;
		ret["_name"] = "IdentExpr";
		ret["isConst"] = isConst;
		return ret;
	}
}

/// `this`
public class ThisExpr : IdentExpr{
public:
	this(){
		this.ident = This;
	}
}

/// `int`
public class IntExpr : IdentExpr{
public:
	this(){
		this.ident = "int";
	}
}

/// `uint`
public class UIntExpr : IdentExpr{
public:
	this(){
		this.ident = "uint";
	}
}

/// `float`
public class FloatExpr : IdentExpr{
public:
	this(){
		this.ident = "float";
	}
}

/// `char`
public class CharExpr : IdentExpr{
public:
	this(){
		this.ident = "char";
	}
}

/// `string`
public class StringExpr : IdentExpr{
public:
	this(){
		this.ident = "string";
	}
}

/// `bool`
public class BoolExpr : IdentExpr{
public:
	this(){
		this.ident = "bool";
	}
}

// Operators / Base -----------------------------------------------------------

/// postscript operator
public abstract class OpPostExpr : Expression{
public:
	/// operator
	string op;
	/// operand
	Expression operand;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["op"] = op;
		ret["operand"] = operand.jsonOf;
		ret["_name"] = "OpPostExpr";
		return ret;
	}
}

/// overridable postscript operator
public abstract class OpPostExprOverridable : OpPostExpr{
public:
	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpPostExprOverridable";
		return ret;
	}
}

/// prefix operator
public abstract class OpPreExpr : Expression{
public:
	/// operator
	string op;
	/// operand
	Expression operand;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["op"] = op;
		ret["operand"] = operand.jsonOf;
		ret["_name"] = "OpPreExpr";
		return ret;
	}
}

/// overridable prefix operator
public abstract class OpPreExprOverridable : OpPreExpr{
public:
	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpPreExprOverridable";
		return ret;
	}
}

/// binary operator
public abstract class OpBinExpr : Expression{
public:
	/// operator
	string op;
	/// left operand
	Expression lhs;
	/// right operand
	Expression rhs;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["op"] = op;
		ret["lhs"] = lhs.jsonOf;
		ret["rhs"] = rhs.jsonOf;
		ret["_name"] = "OpBinExpr";
		return ret;
	}
}

/// overridable binary operator
public abstract class OpBinExprOverridable : OpBinExpr{
public:
	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpBinExprOverridable";
		return ret;
	}
}

/// call expression
public class OpCallExpr : Expression{
public:
	/// callee
	Expression callee;
	/// parameters
	Expression[] params;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["callee"] = callee.jsonOf;
		ret["params"] = params.map!(a => a.jsonOf).array;
		ret["_name"] = "OpCallExpr";
		return ret;
	}
}

/// index expression
public class OpIndexExpr : Expression{
public:
	/// lhs
	Expression lhs;
	/// indexes
	Expression[] indexes;

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["lhs"] = lhs.jsonOf;
		ret["indexes"] = indexes.map!(a => a.jsonOf).array;
		ret["_name"] = "OpIndexExpr";
		return ret;
	}
}

// Operators / Assign ---------------------------------------------------------

/// OpAssign binary operator
public class OpAssignBin : OpBinExpr{
public:
	this(){
		this.op = "=";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpAssignBin";
		return ret;
	}
}

// Operators / Post -----------------------------------------------------------

/// OpRefPost postfix operator
public class OpRefPost : OpPostExpr{
public:
	this(){
		this.op = "@";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpRefPost";
		return ret;
	}
}

/// OpInc postfix operator
public class OpIncPost : OpPostExprOverridable{
public:
	this(){
		this.op = "++";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpIncPost";
		return ret;
	}
}

/// OpDec postfix operator
public class OpDecPost : OpPostExprOverridable{
public:
	this(){
		this.op = "--";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpDecPost";
		return ret;
	}
}

/// OpDots postfix operator
public class OpDotsPost : OpPostExpr{
public:
	this(){
		this.op = "...";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpDotsPost";
		return ret;
	}
}

// Operators / Pre ------------------------------------------------------------

/// OpIsPre prefix operator
public class OpIsPre : OpPreExpr{
public:
	this(){
		this.op = "is";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpIsPre";
		return ret;
	}
}

/// OpNotIsPre prefix operator
public class OpNotIsPre : OpPreExpr{
public:
	this(){
		this.op = "!is";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpNotIsPre";
		return ret;
	}
}

/// OpConst prefix operator
public class OpConstPre : OpPreExpr{
public:
	this(){
		this.op = "const";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpConstPre";
		return ret;
	}
}

/// OpNot prefix operator
public class OpNotPre : OpPreExprOverridable{
public:
	this(){
		this.op = "!";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpNotPre";
		return ret;
	}
}

/// OpRef prefix operator
public class OpRefPre : OpPreExpr{
public:
	this(){
		this.op = "@";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpRefPre";
		return ret;
	}
}

/// OpTag prefix operator
public class OpTagPre : OpPreExpr{
public:
	this(){
		this.op = "#";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpTagPre";
		return ret;
	}
}

/// OpBitNot prefix operator
public class OpBitNotPre : OpPreExprOverridable{
public:
	this(){
		this.op = "~";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpBitNotPre";
		return ret;
	}
}

// Operators / Bin ------------------------------------------------------------

/// OpArrow binary operator
public class OpArrowBin : OpBinExpr{
public:
	this(){
		this.op = "->";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpArrowBin";
		return ret;
	}
}

/// OpComma binary operator
public class OpCommaBin : OpBinExpr{
public:
	this(){
		this.op = ",";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpCommaBin";
		return ret;
	}
}

/// OpDot binary operator
public class OpDotBin : OpBinExpr{
public:
	this(){
		this.op = ".";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpDotBin";
		return ret;
	}
}

/// OpMul binary operator
public class OpMulBin : OpBinExprOverridable{
public:
	this(){
		this.op = "*";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpMulBin";
		return ret;
	}
}

/// OpDiv binary operator
public class OpDivBin : OpBinExprOverridable{
public:
	this(){
		this.op = "/";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpDivBin";
		return ret;
	}
}

/// OpMod binary operator
public class OpModBin : OpBinExprOverridable{
public:
	this(){
		this.op = "%";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpModBin";
		return ret;
	}
}

/// OpAdd binary operator
public class OpAddBin : OpBinExprOverridable{
public:
	this(){
		this.op = "+";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpAddBin";
		return ret;
	}
}

/// OpSub binary operator
public class OpSubBin : OpBinExprOverridable{
public:
	this(){
		this.op = "-";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpSubBin";
		return ret;
	}
}

/// OpLS binary operator
public class OpLSBin : OpBinExprOverridable{
public:
	this(){
		this.op = "<<";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpLSBin";
		return ret;
	}
}

/// OpRS binary operator
public class OpRSBin : OpBinExprOverridable{
public:
	this(){
		this.op = ">>";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpRSBin";
		return ret;
	}
}

/// OpEq binary operator
public class OpEqBin : OpBinExprOverridable{
public:
	this(){
		this.op = "==";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpEqBin";
		return ret;
	}
}

/// OpNotEq binary operator
public class OpNotEqBin : OpBinExprOverridable{
public:
	this(){
		this.op = "!=";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpNotEqBin";
		return ret;
	}
}

/// OpGrEq binary operator
public class OpGrEqBin : OpBinExprOverridable{
public:
	this(){
		this.op = ">=";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpGrEqBin";
		return ret;
	}
}

/// OpLsEq binary operator
public class OpLsEqBin : OpBinExprOverridable{
public:
	this(){
		this.op = "<=";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpLsEqBin";
		return ret;
	}
}

/// OpGr binary operator
public class OpGrBin : OpBinExprOverridable{
public:
	this(){
		this.op = ">";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpGrBin";
		return ret;
	}
}

/// OpLs binary operator
public class OpLsBin : OpBinExprOverridable{
public:
	this(){
		this.op = "<";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpLsBin";
		return ret;
	}
}

/// OpColon binary operator
public class OpColonBin : OpBinExpr{
public:
	this(){
		this.op = ":";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpColonBin";
		return ret;
	}
}

/// OpIs binary operator
public class OpIsBin : OpBinExpr{
public:
	this(){
		this.op = "is";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpIsBin";
		return ret;
	}
}

/// OpNotIs binary operator
public class OpNotIsBin : OpBinExpr{
public:
	this(){
		this.op = "!is";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpNotIsBin";
		return ret;
	}
}

/// OpBitAnd binary operator
public class OpBitAndBin : OpBinExprOverridable{
public:
	this(){
		this.op = "&";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpBitAndBin";
		return ret;
	}
}

/// OpBitOr binary operator
public class OpBitOrBin : OpBinExprOverridable{
public:
	this(){
		this.op = "|";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpBitOrBin";
		return ret;
	}
}

/// OpBitXor binary operator
public class OpBitXorBin : OpBinExprOverridable{
public:
	this(){
		this.op = "^";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpBitXorBin";
		return ret;
	}
}

/// OpAnd binary operator
public class OpAndBin : OpBinExpr{
public:
	this(){
		this.op = "&&";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpAndBin";
		return ret;
	}
}

/// OpOr binary operator
public class OpOrBin : OpBinExpr{
public:
	this(){
		this.op = "||";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpOrBin";
		return ret;
	}
}

// Operators / Errors ---------------------------------------------------------

/// OpQ postfix operator
public class OpQPost : OpPostExpr{
public:
	this(){
		this.op = "?";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpQPost";
		return ret;
	}
}

/// OpQQ binary operator
public class OpQQBin : OpBinExpr{
public:
	this(){
		this.op = "??";
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "OpQQBin";
		return ret;
	}
}

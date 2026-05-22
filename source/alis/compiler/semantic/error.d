/++
Alis Semantic Errors
+/
module alis.compiler.semantic.error;

import alis.compiler.common,
			 alis.compiler.ast,
			 alis.common;

import std.format,
			 std.conv,
			 std.traits,
			 std.range;

/// Value or SmErr
alias SmErrVal(T) = ErrVal!(T, SmErr);
/// Value or SmErrs
alias SmErrsVal(T) = ErrVal!(T, SmErr[]);

/// Alis Semantic Error
public struct SmErr{
	/// Possible Error Types
	enum Type{
		IdentReuse, /// Same identifier used across definitions
		UnsupFeat, /// Unsupported Feature used
		ValExprExpected, /// Expression should have resolved to value
		TypeExprExpected, /// Expression should have resolved to type
		SymExprExpected, /// Expression should have resolved to symbol
		ParamCountMis, /// mismatched parameter count
		RecursiveDep, /// Recursive Dependency
		IncompatTypes, /// incompatible types
		EnumMemValMis, /// enum member value missing
		MultiInherit, /// multiple alias `this`
		FieldThis, /// field named `this`
		AutoNoVal, /// Cannot have auto when no value provided
		UnionMultiDef, /// Union has more than one default values
		UnionNoDef, /// Union has no default value
		UnUnionTypeUnique, /// Unnamed union must have unique types
		FParamNoDef, /// Function Parameter expected to have default value
		Unxp, /// Unexpected error in compiler
		IdentAmbig, /// Ambiguous identifier
		FnAnonParamDef, /// Anonymous Function cannot have default parameter value
		TypeInferFail, /// Failed to infer type
		Bounds, /// Bounds violation
		CallableIncompat, /// Callable symbol called with incompatible params
		NotCallable, /// Callable expected, not found (sadly)
		CallableConflict, /// Multiple callables matched
		Undef, /// use of undefined identifier
		AssignConst, /// assigning to const
		AssignRef, /// assigning to ref using =
		NotRef, /// Expected ref, is not ref
		DerefNoRef, /// trying to deref something that is not a ref
		ConstConst, /// trying to const a const
		IntrUnk, /// unknown intrinsic
		MemberNoExist, /// Member not existing
		Err, /// error through the $err intrinsic
		InitFail, /// Cannot initialize a value
		NoReturn, /// Missing return
		RefNonRefable, /// Trying to reference a non-referenceable
		AutoConstIncompat, /// Using `auto const` where not allowed
	}

	/// where error happen
	Location pos;
	/// error message
	string msg;
	/// type
	Type type;
	/// string representation
	string toString() const pure {
		return format!"%s: %s"(pos, msg);
	}
	@disable this();
	this (Location pos, string msg, Type type){
		this.pos = pos;
		this.msg = msg;
		this.type = type;
	}
}

/// Identifier re-use error
package SmErr errIdentReuse(Location pos, string ident){
	return SmErr(pos, format!"identifier `%s` conflicts"(ident),
			SmErr.Type.IdentReuse);
}

/// Unsupported AST node
package SmErr errUnsup(ASTNode node){
	return SmErr(node.pos,
			typeid(node).to!string.format!"unsupported node `%s`",
			SmErr.Type.UnsupFeat);
}

/// Unsupported Feature
package SmErr errUnsup(Location pos, string feat){
	return SmErr(pos, feat.format!"unsupported feature: %s",
			SmErr.Type.UnsupFeat);
}

/// Expression should have resolved to Value
package SmErr errExprValExpected(Location pos){
	return SmErr(pos,
			format!"expression does not evaluate to value",
			SmErr.Type.ValExprExpected);
}

/// Expression should have resolved to type
package SmErr errExprTypeExpected(Location pos){
	return SmErr(pos,
			format!"expression does not evaluate to type",
			SmErr.Type.TypeExprExpected);
}

/// Expression should have resolved to Symbol
package SmErr errExprSymExpected(Location pos){
	return SmErr(pos,
			format!"expression does not evaluate to symbol",
			SmErr.Type.SymExprExpected);
}

/// Parameter count mismatch
package SmErr errParamCount(Location pos, string name, size_t expected,
		size_t got){
	return SmErr(pos,
			format!"mismatched parameter count for `%s`: expected %d, received %d"(
				name, expected, got),
			SmErr.Type.ParamCountMis);
}
/// Recursive Dependency
package SmErr errRecDep(Location pos, string name){
	return SmErr(pos,
			name.format!"recursive dependency on %s",
			SmErr.Type.RecursiveDep);
}

/// incompatible types
package SmErr errIncompatType()(Location pos, string expected,
		string got){
	return SmErr(pos,
			format!"incompatible types: cannot implicitly cast `%s` to `%s`"(
				got, expected),
			SmErr.Type.IncompatTypes);
}

/// incompatible types in enum values
package SmErr errIncompatType(EnumDef node){
	return SmErr(node.pos,
			format!"incompatible types: enum %s members of incompatible types"(
				node.name), SmErr.Type.IncompatTypes);
}

/// enum member value missing
package SmErr errEnumMemValMis(EnumMember member){
	return SmErr(member.pos, member.name.format!"enum member %s has no value",
			SmErr.Type.EnumMemValMis);
}

/// multiple inheritence
package SmErr errMultiInherit(Location pos){
	return SmErr(pos, "multiple `alias this`", SmErr.Type.MultiInherit);
}

/// field named `this`
package SmErr errFieldThis(Location pos){
	return SmErr(pos, "field cannot be named `this`", SmErr.Type.FieldThis);
}

/// Cannot have auto when no value provided
package SmErr errAutoNoVal(Location pos){
	return SmErr(pos, "cannot infer auto type in absense of value",
			SmErr.Type.AutoNoVal);
}

/// Union has more than one default values
package SmErr errUnionMultiDef(Location pos){
	return SmErr(pos, "union cannot have more than one default value",
			SmErr.Type.UnionMultiDef);
}
/// Union has no default value
package SmErr errUnionNoDef(Location pos){
	return SmErr(pos, "union has no default value",
			SmErr.Type.UnionNoDef);
}

/// Unnamed union must have unique types
package SmErr errUnUnionTypeUnique(Location pos, ADataType a, ADataType b){
	return SmErr(pos,
			format!"unnamed union's types must be unique: %s is compatible with %s"(
				a, b), SmErr.Type.UnUnionTypeUnique);
}

/// Function Parameter expected to have default value
package SmErr errFParamNoDef(Location pos, string name){
	return SmErr(pos,
			name.format!"function parameter %s should have default value",
			SmErr.Type.FParamNoDef);
}

/// Unexpected error in compiler
package SmErr errUnxp(Location pos, string err){
	return SmErr(pos, err, SmErr.Type.Unxp);
}

/// Ambiguous identifier
package SmErr errIdentAmbig(R)(Location pos, string ident, R matches) if (
		isInputRange!(R, string)){
	return SmErr(pos,
			format!"identifier %s is ambiguous, matches with: %(%r,%)"(
				ident, matches), SmErr.Type.IdentAmbig);
}

/// Anonymous Function cannot have default parameter value
package SmErr errFnAnonParamDef(Location pos, string name){
	return SmErr(pos,
			format!"anonymous function parameter `%s` cannot have default value"(
				name), SmErr.Type.FnAnonParamDef);
}

/// Failed to infer type
package SmErr errTypeInferFail(Location pos, string name){
	return SmErr(pos, name.format!"type inference failed for `%s`",
			SmErr.Type.TypeExprExpected);
}

/// Bounds violation
package SmErr errBounds(Location pos, size_t max, size_t got){
	return SmErr(pos, format!"bounds violation: %d exceeds bound %d"(
				got, max), SmErr.Type.Bounds);
}
/// Callable symbol called with incompatible params
package SmErr errCallableIncompat(R)(Location pos, string symN, R range) if (
		isInputRange!(R, string)){
	return SmErr(pos,
			format!"incompatible parameters: `%s` cannot be called with (%(%r,%))"(
				symN, range), SmErr.Type.CallableIncompat);
}

/// Callable expected, not found (sadly)
package SmErr errNotCallable(Location pos, string symN){
	return SmErr(pos, symN.format!"callable expected: `%s` is not callable",
			SmErr.Type.NotCallable);
}

/// Multiple callables matched
package SmErr errCallableConflict(R)(Location pos, string symN, R range) if (
		isInputRange!(R, string)){
	return SmErr(pos,
			format!"ambiguous call: for callable `%s` with parameters %(%r%)"(
				symN, range), SmErr.Type.CallableConflict);
}
/// ditto
package SmErr errCallableConflict(R0, R1)(Location pos,
		R0 paramsA, R1 paramsB) if (
		isInputRange!(R0, string) && isInputRange!(R1, string)){
	return SmErr(pos,
			format!"ambiguous call: matches with both: (%(%r%)) and (%(%r%))"(
				paramsA, paramsB), SmErr.Type.CallableConflict);
}

/// use of undefined identifier
package SmErr errUndef(Location pos, string id){
	return SmErr(pos, id.format!"undefined identifier: `%s`", SmErr.Type.Undef);
}

/// assigning to const
package SmErr errAssignConst(Location pos, string type){
	return SmErr(pos,
			type.format!"assignment to const: cannot assign to type `%s`",
			SmErr.Type.AssignConst);
}

/// assigning to ref using =
package SmErr errAssignRef(Location pos){
	return SmErr(pos, "assignment to ref: cannot use `=` to assign to ref",
			SmErr.Type.AssignRef);
}

/// Expected ref, is not ref
package SmErr errNotRef(Location pos){
	return SmErr(pos, "reference expected", SmErr.Type.NotRef);
}

/// trying to deref something that is not a ref
package SmErr errDerefNoRef(Location pos, string type){
	return SmErr(pos,
			type.format!"only reference can be dereferenced: cannot deref `%s`",
			SmErr.Type.DerefNoRef);
}

/// trying to const a const
package SmErr errConstConst(Location pos, string type){
	return SmErr(pos, type.format!"constOf const: cannot const `%s`",
			SmErr.Type.ConstConst);
}

/// unknown intrinsic
package SmErr errIntrUnk(Location pos, string intrN){
	return SmErr(pos, intrN.format!"unknown intrinsic: `%s`", SmErr.Type.IntrUnk);
}

/// Member not existing
package SmErr errMemberNoExist(Location pos, string sym, string mem){
	return SmErr(pos,
			format!"inaccessible member: member `%s` for `%s` cannot be accessed"(
				sym, mem), SmErr.Type.MemberNoExist);
}

/// $err intrinsic error
package SmErr errErr(Location pos, string err){
	return SmErr(pos, err.format!"$err: %s", SmErr.Type.Err);
}

/// Cannot initialize a value
package SmErr errInitFail(Location pos, string type){
	return SmErr(pos,
			type.format!"initialization error: cannot initialize type `%s`",
			SmErr.Type.InitFail);
}

/// ditto
package SmErr errInitFail(Location pos, string type, string subType){
	return SmErr(pos,
			format!"initialization error: cannot initialize type `%s` in `%s`"(
				subType, type),
			SmErr.Type.InitFail);
}

/// Missing return
package SmErr errNoReturn(Location pos, string expected){
	return SmErr(pos,
			expected.format!"missing return: expected return type `%s`",
			SmErr.Type.NoReturn);
}

/// Trying to reference a non-referenceable
package SmErr errRefNonRefable(Location pos, string val){
	return SmErr(pos,
			format!"cannot reference value `%s"(val),
			SmErr.Type.RefNonRefable);
}

/// Using `auto const` where not allowed
package SmErr errAutoConstIncompat(Location pos){
	return SmErr(pos, "Using `auto const` here is not allowed",
			SmErr.Type.AutoConstIncompat);
}

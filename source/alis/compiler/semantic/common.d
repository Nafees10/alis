/++
Semantic Analysis common stuff
+/
module alis.compiler.semantic.common;

import alis.common,
			 alis.compiler.common,
			 alis.compiler.ast,
			 alis.compiler.ast.rst,
			 meta;

import std.algorithm,
			 std.range,
			 std.json,
			 std.meta,
			 std.traits,
			 std.format,
			 std.conv;

debug import std.stdio;

/// Partial call to a resolved expr
/// **should never occur in a finalized RST**
package class RPartCallExpr : RExpr{
package:
	RExpr callee;
	AValCT[] params;
	this(){}
public:
	override string toString() const pure {
		return callee.format!"RPartCallExpr %s (%(%s,%))"(params);
	}
}

/// Resolved Partial Template Instantiation Expression
/// **should never occur in a finalized RST**
package class RTmPartInitExpr : RExpr{
package:
	// TODO: include expected param types
	this(){}
	// TODO
public:
	override string toString() const pure {
		return "RTmPartInitExpr";
	}
}

/// Resolved Partial Intrinsic Call Expression
/// **should never occur in a finalized RST**
package class RIntrinsicPartCallExpr : RExpr{
package:
	/// intrinsic name
	string name;
	/// parameters
	AValCT[] params;
	this(){}
public:
	override string toString() const pure {
		return "RIntrinsicPartCallExpr";
	}
}

/// Enum Member Get Expression
package class REnumMemberGetExpr : RLiteralExpr{
package:
	/// enum
	AEnum* enumS;
	/// member name
	string name;

	this (AVal val, AEnum* enumS, string name){
		super(val);
		this.enumS = enumS;
		this.name = name;
	}
}

/// Enum Const Get Expression
package class REnumConstGetExpr : RLiteralExpr{
package:
	/// EnumConst
	AEnumConst* enumCS;

	this (AVal val, AEnumConst* enumCS){
		super(val);
		this.enumCS = enumCS;
	}
}

/// an Alis CompileTime Value
public struct AValCT{
	/// possible types
	enum Type{
		Literal, /// some Literal value
		Symbol, /// an alias to a symbol
		Type, /// a Data Type
		Expr, /// an alias to an RExpr
		Seq, /// alias (sequence)
	}

	/// Returns: true if this can be implicitly casted to target
	bool canCastTo(const ADataType target, IdentU[] ctx = null){
		if (ctx is null)
			ctx = [IdentU.init];
		import alis.compiler.semantic.error : SmErrsVal;
		final switch (type){
			case Type.Literal:
				return val.canCastTo(target, ctx);
			case Type.Symbol:
				OptVal!ADataType t = symS.valType;
				return t.isVal && t.val.canCastTo(target, ctx);
			case Type.Type:
				return typeT.canCastTo(target, ctx);
			case Type.Expr:
				return expr.canCastTo(target, ctx);
			case Type.Seq:
				debug stderr.writefln!"STUB: Seq.canCastTo -> false";
				return false;
		}
	}

	/// converts this AValCT to a `target` type
	/// only call this if `this.canCastTo(target)` and `this.isVal`
	/// Returns: converted AValCT, or nothing in case it cannot be done
	OptVal!AValCT to(ADataType target, IdentU[] ctx = null){
		if (ctx is null)
			ctx = [IdentU.init];
		assert (canCastTo(target, ctx));
		assert (isVal);
		final switch (type){
			case Type.Literal:
				OptVal!AVal v = val.to(target, ctx);
				if (v.isVal)
					return v.val.AValCT.OptVal!AValCT;
				goto case;
			case Type.Symbol:
			case Type.Type:
				return OptVal!AValCT();
			case Type.Expr:
				 OptVal!RExpr r = expr.to(target, ctx);
				 if (r.isVal)
					 return AValCT(r.val).OptVal!AValCT;
				 return OptVal!AValCT();
			case Type.Seq:
				AValCT[] s = new AValCT[seq.length];
				foreach (size_t i, AValCT val; seq){
					OptVal!AValCT convd = val.to(target, ctx);
					if (!convd.isVal)
						return OptVal!AValCT();
					s[i] = convd.val;
				}
				return s.AValCT.OptVal!AValCT;
		}
	}

	/// whether this is a value
	@property bool isVal(){
		final switch (type){
			case Type.Literal:
				return true;
			case Type.Symbol:
				return symS.isVal;
			case Type.Type:
				return false;
			case Type.Expr:
				if (RAValCTExpr sub = cast(RAValCTExpr)expr)
					return sub.res.isVal;
				return true;
			case Type.Seq:
				return false;
		}
	}

	/// Returns: data type of value, if `isVal`
	OptVal!ADataType valType(){
		final switch (type){
			case Type.Literal:
				return val.type.OptVal!ADataType;
			case Type.Symbol:
				return symS.valType;
			case Type.Type:
				return typeT.OptVal!ADataType;
			case Type.Expr:
				return expr.type.OptVal!ADataType;
			case Type.Seq:
				return OptVal!ADataType();
		}
	}

	/// currently stored type
	Type type = Type.Type;
	union{
		AVal val; /// value for `Literal`
		ASymbol* symS; /// symbol for `Symbol`
		ADataType typeT; /// data type for `Type`
		RExpr expr; /// expr in case of `Expr`
		AValCT[] seq; /// sequence in case of `Seq`
	}

	string toString() const pure {
		final switch (type){
			case Type.Literal:
				return val.toString;
			case Type.Symbol:
				return symS.toString;
			case Type.Type:
				return typeT.toString;
			case Type.Expr:
				return expr.toString;
			case Type.Seq:
				return seq.map!(s => s.toString).join(",").format!"(%s)";
		}
		return null;
	}

	/// constructor
	this (AVal val){
		this.type = Type.Literal;
		this.val = val;
	}
	/// ditto
	this (ASymbol* symS){
		this.type = Type.Symbol;
		this.symS = symS;
	}
	/// ditto
	this (ADataType typeT){
		this.type = Type.Type;
		this.typeT = typeT;
	}
	/// ditto
	this (RExpr expr){
		if (RAValCTExpr rExpr = cast(RAValCTExpr)expr){
			this = rExpr.res;
		} else {
			this.type = Type.Expr;
			this.expr = expr;
		}
	}
	/// ditto
	this (AValCT[] seq){
		this.type = Type.Seq;
		this.seq = seq.dup;
	}

	/// Returns: if this is a data type
	bool isDType(){
		final switch (type){
			case Type.Symbol:
				return symS.isDType;
			case Type.Literal:
			case Type.Expr:
				return false;
			case Type.Type:
				return true;
			case Type.Seq:
				return seq
					.map!(v => v.isDType)
					.fold!((a, b) => a && b);
		}
	}

	/// Gets Data Type associated with this AValCT.
	/// In case of symbol, Struct/Union/Enum becomes the type, otherwise none
	/// In case of Literal, the data's type becomes the type
	/// In case of Type, returned as-is
	/// In case of Expr, returns return type
	/// Returns: Optional ADataType
	OptVal!ADataType asType(){
		final switch (type){
			case Type.Symbol:
				return symS.asType;
			case Type.Literal:
				return val.type.OptVal!ADataType;
			case Type.Type:
				return typeT.OptVal!ADataType;
			case Type.Expr:
				if (expr.hasType)
					return expr.type.OptVal!ADataType;
				return OptVal!ADataType();
			case Type.Seq:
				return OptVal!ADataType();
		}
	}

	/// Returns: new flattened AValCT[]
	public AValCT[] flatten(){
		if (type != AValCT.Type.Seq)
			return [this];
		return seq.dup;
	}
}

/// flattens AValCT[]
/// Returns: new flattened AValCT[]
public AValCT[] flatten(AValCT[] seq){
	size_t i = 0;
	while (i < seq.length){
		if (seq[i].type == AValCT.Type.Seq)
			break;
		i ++;
	}
	if (i >= seq.length) return seq.dup;
	AValCT[] ret = seq[0 .. i].dup;
	foreach (ref AValCT val; seq[i .. $]){
		if (val.type == AValCT.Type.Seq)
			ret ~= val.seq.flatten;
		else
			ret ~= val;
	}
	return ret;
}

/// Returns: true if an AValCT[] is flat
public bool isFlat(AValCT[] seq){
	foreach (AValCT val; seq){
		if (val.type == AValCT.Type.Seq)
			return false;
	}
	return true;
}

/// Wrapper for AValCT
/// **should never occur in a finalized RST**
package class RAValCTExpr : RExpr{
public:
	/// evaluation result
	AValCT res;

	this (){}
	this(AValCT res){
		assert (res.type != AValCT.Type.Expr);
		this.res = res;
		if (res.isVal)
			this.type = res.valType.val;
	}

	override JSONValue jsonOf() const pure {
		JSONValue ret = super.jsonOf;
		ret["_name"] = "RAValCTExpr";
		ret["res"] = res.toString;
		return ret;
	}

	/// convert to an actual RExpr
	final RExpr toRExpr(){
		final switch (res.type){
			case AValCT.Type.Literal:
				RLiteralExpr r = new RLiteralExpr(AVal(res.val.type, res.val.data));
				r.pos = pos;
				return r;
			case AValCT.Type.Symbol:
			case AValCT.Type.Type:
			case AValCT.Type.Seq:
				assert (false, "unsupported AValCT.Type in RAValCTExpr.toRExpr");
			case AValCT.Type.Expr:
				return res.expr;
		}
	}

	override string toString() const pure {
		return format!"$AValCT(%s)"(res);
	}
}

/// converts/wraps an AValCT into RExpr
RExpr toRExpr()(auto ref AValCT val){
	final switch (val.type){
		case AValCT.Type.Literal:
			return new RLiteralExpr(val.val); // TODO: set pos
		case AValCT.Type.Symbol:
		case AValCT.Type.Type:
			return new RAValCTExpr(val); // TODO: set pos
		case AValCT.Type.Expr:
			return val.expr;
		case AValCT.Type.Seq:
			assert (false, "cannot toRExpr AValCT of Type.Seq");
	}
}

/// Iterator Function Level
package struct ITL{
	size_t level;
	@disable this();
	this(size_t level){
		this.level = level;
	}
}

/// AST Iterator, using ItFns from module `M`, that are tagged with `ITL(L)`
package template ItL(alias M, size_t L){
	// yes, I know Fns not used. go ahead, remove it, I dare you.
	alias Fns = AliasSeq!();
	static foreach (F; ItFnsOf!M){
		static if (hasUDA!(F, ITL(L))){
			Fns = AliasSeq!(Fns, F);
		}
	}
	alias ItL = ASTIter!(Filter!(HasAnyUDA!(ITL(L)), ItFnsOf!M));
}

/// RST Iterator, using ItFns from module `M`, that are tagged with `ITL(L)`
package template RtL(alias M, size_t L){
	// yes, I know Fns not used. go ahead, remove it, I dare you.
	alias Fns = AliasSeq!();
	static foreach (F; ItFnsOf!M){
		static if (hasUDA!(F, ITL(L))){
			Fns = AliasSeq!(Fns, F);
		}
	}
	static import alis.compiler.ast.iter;
	alias Iter(Fns...) =
		Instantiate!(alis.compiler.ast.iter.ASTIter!(RSTNodes, RAValCTExpr), Fns);
	alias RtL = Iter!(Filter!(HasAnyUDA!(ITL(L)), ItFnsOf!M));
}

/// Semantic Analysis Context
package struct SmCtx{
	@disable this();
	/// symbol table local
	STab stab;
	/// symbol table root
	STab stabR;
	/// context
	IdentU[] ctx;
	/// symbols dependent upon current call
	void[0][ASymbol*] dep;

	this(STab stabR, void[0][ASymbol*] dep, IdentU[] ctx){
		this.stabR = stabR;
		this.ctx = ctx;
		this.dep = dep;
	}
	this(STab stab, STab stabR, void[0][ASymbol*] dep, IdentU[] ctx){
		this.stab = stab;
		this.stabR = stabR;
		this.ctx = ctx;
		this.dep = dep;
	}
}

/// Symbol Table
public final class STab{
public:
	struct Node(E){
		E val;
		IdentU[] vis;
		this (E val, IdentU[] vis) pure {
			this.val = val;
			this.vis = vis.dup;
		}
		/// Returns: whether this is visible from a ctx
		bool isVis(IdentU[] ctx) const pure {
			if (ctx.isNoId || vis.isNoId)
				return true;
			if (ctx.length < vis.length)
				return false;
			return vis == ctx[0 .. vis.length];
		}
	}

	/// the symbol table
	Node!(ASymbol*)[][IdentU] map;
	/// sub-tables
	Node!STab[IdentU] next;

	static struct ResRange{
	private:
		IdentU _id;
		IdentU[] _ctx;
		Node!(ASymbol*)[][IdentU][] _maps;

		this(IdentU id, IdentU[] ctx, STab st) pure {
			this._id = id;
			this._ctx = ctx.dup;
			_maps ~= st.map;
			foreach (IdentU i; _ctx){
				if (i !in st.next)
					break;
				Node!STab nextNode = st.next[i];
				if (!nextNode.isVis(_ctx))
					break;
				_maps ~= nextNode.val.map;
				st = nextNode.val;
			}
			_maps ~= ForeachType!(typeof(_maps)).init;
			popFront;
		}

	public:
		@disable this();
		this(this){}
		bool empty() pure {
			return _maps.length == 0;
		}
		void popFront() pure {
			if (empty)
				return;
			_maps = _maps[0 .. $ - 1];
			while (_maps.length && front.empty)
				_maps = _maps[0 .. $ - 1];
		}
		auto front() pure {
			Node!(ASymbol*)[] arr;
			if (_maps.length && (_id in _maps[$ - 1]) !is null)
				arr = _maps[$ - 1][_id];
			return arr
				.filter!(node => node.isVis(_ctx))
				.map!(node => node.val);
		}
	}

	/// finds all candidates that match an IdentU, given a scope ctx
	/// Returns: range of candidates
	ResRange find(IdentU id, IdentU[] ctx) pure {
		return ResRange(id, ctx, this);
	}

	/// Returns: true if id can be found from ctx scope
	bool canFind(IdentU id, IdentU[] ctx) pure {
		return !(find(id, ctx).empty);
	}

	/// finds STab
	/// Returns: STab or null
	STab findSt(IdentU id, IdentU[] ctx) pure {
		if (Node!STab* ptr = id in next){
			if (ptr.isVis(ctx))
				return ptr.val;
		}
		return null;
	}

	/// ditto
	STab findSt(IdentU[] id, IdentU[] ctx) pure {
		STab ret = this;
		foreach (IdentU i; id){
			ret = ret.findSt(i, ctx);
			if (ret is null)
				return null;
		}
		return ret;
	}

	/// Add a new value.
	void add(IdentU id, ASymbol* sym, IdentU[] vis) pure {
		if (!vis.length)
			vis = [IdentU.init];
		if (auto ptr = id in map){
			*ptr ~= Node!(ASymbol*)(sym, vis);
			return;
		}
		map[id] = [Node!(ASymbol*)(sym, vis)];
	}
	/// ditto
	void add(IdentU id, ASymbol* sym, Visibility vis, IdentU[] ctx) pure {
		return add(id, sym, vis == Visibility.Default ? ctx : [IdentU.init]);
	}

	/// Add a new Symbol Table. **Will overwrite existing, if any.**
	void add(IdentU id, STab st, IdentU[] vis) pure {
		if (!vis.length)
			vis = [IdentU.init];
		next[id] = Node!STab(st, vis);
	}
	/// ditto
	void add(IdentU id, STab st, Visibility vis, IdentU[] ctx) pure {
		return add(id, st, vis == Visibility.Default ? ctx : [IdentU.init]);
	}

	/// Returns: nonCallable symbol at this level, by its IdentU. Will return
	/// `null` if none present, or none visible.
	ASymbol* localNonCallable(IdentU id, IdentU[] ctx) pure {
		if (id !in map)
			return null;
		auto range = map[id]
			.filter!(node => node.isVis(ctx) && !node.val.isCallable);
		if (range.empty)
			return null;
		return range.front.val;
	}

	/// Returns: whether a nonCallable symbol exists by certain IdentU, at this
	/// level
	@property bool hasLocalNonCallable(IdentU id, IdentU[] ctx) pure {
		return localNonCallable(id, ctx) !is null;
	}

	JSONValue jsonOf() const {
		JSONValue ret;
		foreach (IdentU key; map.byKey){
			ret[key.toString] = map[key]
				.map!((const Node!(ASymbol*) n){
						JSONValue obj;
						static if (__traits(compiles, n.val.jsonOf)){
							obj["val"] = n.val.jsonOf;
						} else {
							obj["val"] = n.val.toString;
						}
						obj["vis"] = n.vis.to!string;
						return obj;
						})
				.array;
		}
		if (ret.isNull)
			ret = JSONValue.emptyObject;
		foreach (IdentU key; next.byKey){
			immutable string s = key.toString;
			const Node!STab n = next[key];
			JSONValue obj;
			obj["val"] = n.val.jsonOf;
			obj["vis"] = n.vis.to!string;
			if (s in ret.object)
				ret[s] ~= obj;
			else
				ret[s] = [obj];
		}
		return ret;
	}

	override string toString() const {
		return jsonOf.toPrettyString;
	}
}

/// Alis Template Resolution Node. Usually for tracking resolution across
/// aliases
package struct ATResN{
private:
	ATResN* _leaf;
	ATResN* _next;
	ATResN* _prev;

public:
	/// what is being resolved
	IdentU[] subject;
	/// result from resolution
	ASymbol* sym;

	/// previous resolution, if any
	@property ATResN* prev() const pure {
		return cast(ATResN*)_prev;
	}
	/// next resolution, if any
	@property ATResN* next() const pure {
		return cast(ATResN*)_next;
	}
	/// Returns: most resolved Resolution. will be `this` if `next is null`
	@property ATResN* leaf() pure {
		if (_leaf is null){
			if (_next is null)
				return _leaf = &this;
			return _leaf = next.leaf;
		}
		if (_leaf.next){
			_leaf._leaf = null;
			return _leaf = _leaf.leaf;
		}
		return _leaf;
	}
	/// pushes a new resolution at end of this list
	void push(ATResN* r) pure {
		leaf._next = r;
	}
}

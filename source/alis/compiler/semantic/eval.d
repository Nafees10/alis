/++
Expression (RExpr) Compile Time Evaluation
+/
module alis.compiler.semantic.eval;

import alis.common,
			 alis.compiler.common,
			 alis.compiler.semantic.common,
			 alis.compiler.semantic.error,
			 alis.compiler.semantic.types,
			 alis.compiler.ast,
			 alis.compiler.ast.iter,
			 alis.compiler.ast.rst;

import alis.compiler.semantic.expr : resolve;

import meta;

import std.algorithm,
			 std.range,
			 std.format;

debug import std.stdio,
			std.conv;

private alias It = RtL!(mixin(__MODULE__), 0);

struct St{
	/// errors
	SmErr[] errs;
	/// root STab
	STab stabR;
	/// local STab
	STab stab;
	/// context ctx
	IdentU[] ctx;
	/// Result
	AValCT res;
}

private SmErrsVal!AValCT eval(AValCT val, STab stabR, IdentU[] ctx){
	final switch (val.type){
		case AValCT.Type.Literal:
		case AValCT.Type.Symbol:
		case AValCT.Type.Type:
			return val.SmErrsVal!AValCT;
		case AValCT.Type.Expr:
			return eval(val.expr, stabR, ctx);
		case AValCT.Type.Seq:
			AValCT[] seq = new AValCT[val.seq.length];
			SmErr[] errs;
			foreach (size_t i, AValCT v; val.seq){
				SmErrsVal!AValCT res = eval(v, stabR, ctx);
				if (res.isErr){
					errs ~= res.err;
					continue;
				}
				seq[i] = res.val;
			}
			if (errs.length){
				return errs.SmErrsVal!AValCT;
			}
			return AValCT(seq).SmErrsVal!AValCT;
	}
}

@ItFn @ITL(0) {
	void literalIter(RLiteralExpr node, ref St st){
		st.res = node.val.AValCT;
	}

	void avalCtIter(RAValCTExpr node, ref St st){
		SmErrsVal!AValCT res = eval(node.res, st.stabR, st.ctx);
		if (res.isErr){
			st.errs ~= res.err;
			return;
		}
		st.res = res.val;
	}

	void exprIter(RExpr node, ref St st){
		st.res = AValCT(node);
		//st.errs ~= errUnsup(node);
	}
}

/// Evaluates an `expr`. Resulting AVAlCT can be any of 3 `AValCT.Type`,
/// in case something is suitable as `Type.Symbol` and something else,
/// `Type.Symbol` will be preferred.
/// Params:
/// - `expr` - The expression to resolve
/// - `stab` - The root level Symbol Table
/// - `ctx` - Context where the `expr` occurs
/// Returns: AValCT, or SmErr[]
package SmErrsVal!AValCT eval(RExpr expr, STab stabR, IdentU[] ctx){
	St st;
	st.stabR = stabR;
	st.stab = stabR.findSt(ctx, ctx);
	st.ctx = ctx.dup;
	It.exec(expr, st);
	if (st.errs.length)
		return SmErrsVal!AValCT(st.errs);
	return SmErrsVal!AValCT(st.res);
}

/// ditto
package SmErrsVal!AValCT eval(Expression expr, STab stab, IdentU[] ctx,
		void[0][ASymbol*] dep, RFn[string] fns, AValCT[] params = null){
	SmErrsVal!RExpr resolved = resolve(expr, stab, ctx, dep, fns, params);
	if (resolved.isErr)
		return SmErrsVal!AValCT(resolved.err);
	return eval(resolved.val, stab, ctx);
}


/// Evaluates an RExpr expecting a value. See `eval`
/// Returns: AValCT with Type.Literal, or SmErr[]
package SmErrsVal!AVal eval4Val(RExpr expr, STab stab, IdentU[] ctx){
	SmErrsVal!AValCT res = eval(expr, stab, ctx);
	if (res.isErr)
		return res.err.SmErrsVal!AVal;
	if (res.val.type != AValCT.Type.Literal)
		return SmErrsVal!AVal([errExprValExpected(expr.pos)]);
	return res.val.val.SmErrsVal!AVal;
}

/// ditto
package SmErrsVal!AVal eval4Val(Expression expr, STab stab, IdentU[] ctx,
		void[0][ASymbol*] dep, RFn[string] fns, AValCT[] params = null){
	SmErrsVal!RExpr resolved = resolve(expr, stab, ctx, dep, fns, params);
	if (resolved.isErr)
		return SmErrsVal!AVal(resolved.err);
	return eval4Val(resolved.val, stab, ctx);
}

/// Evaluates an RExpr expecting a type. See `eval`
/// Returns: ADataType or SmErr[]
package SmErrsVal!ADataType eval4Type(RExpr expr, STab stab, IdentU[] ctx){
	SmErrsVal!AValCT ret = eval(expr, stab, ctx);
	if (ret.isErr)
		return SmErrsVal!ADataType(ret.err);
	if (!ret.val.isDType)
		return SmErrsVal!ADataType([errExprTypeExpected(expr.pos)]);
	OptVal!ADataType typeRes = ret.val.asType;
	if (!typeRes.isVal)
		return SmErrsVal!ADataType([errExprTypeExpected(expr.pos)]);
	return typeRes.val.SmErrsVal!ADataType;
}

/// ditto
package SmErrsVal!ADataType eval4Type(Expression expr, STab stab, IdentU[] ctx,
		void[0][ASymbol*] dep, RFn[string] fns, AValCT[] params = null){
	SmErrsVal!RExpr resolved = resolve(expr, stab, ctx, dep, fns, params);
	if (resolved.isErr)
		return SmErrsVal!ADataType(resolved.err);
	return eval4Type(resolved.val, stab, ctx);
}

/// Evaluates an RExpr expecting a symbol. See `eval`
/// Returns: ASymbol* or SmErr[]
package SmErrsVal!(ASymbol*) eval4Sym(RExpr expr, STab stab, IdentU[] ctx){
	SmErrsVal!AValCT ret = eval(expr, stab, ctx);
	if (ret.isErr)
		return SmErrsVal!(ASymbol*)(ret.err);
	if (ret.val.type != AValCT.Type.Symbol)
		return SmErrsVal!(ASymbol*)([errExprSymExpected(expr.pos)]);
	return SmErrsVal!(ASymbol*)(ret.val.symS);
}

/// ditto
package SmErrsVal!(ASymbol*) eval4Sym(Expression expr, STab stab, IdentU[] ctx,
		void[0][ASymbol*] dep, RFn[string] fns, AValCT[] params = null){
	SmErrsVal!RExpr resolved = resolve(expr, stab, ctx, dep, fns, params);
	if (resolved.isErr)
		return SmErrsVal!(ASymbol*)(resolved.err);
	return eval4Sym(resolved.val, stab, ctx);
}

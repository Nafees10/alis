/++
Expression Resolution (Expression -> RExpr conversion)
+/
module alis.compiler.semantic.expr;

import alis.common,
			 alis.compiler.common,
			 alis.compiler.semantic.common,
			 alis.compiler.semantic.error,
			 alis.compiler.semantic.sym0,
			 alis.compiler.semantic.eval,
			 alis.compiler.semantic.stmnt,
			 alis.compiler.semantic.types,
			 alis.compiler.semantic.call,
			 alis.compiler.semantic.intrinsics,
			 alis.compiler.semantic,
			 alis.compiler.ast,
			 alis.compiler.ast.iter,
			 alis.compiler.ast.rst;

import alis.compiler.semantic.sym1 : unionNamedDo, unionUnnamedDo, structDo;

import meta;

import std.algorithm,
			 std.array,
			 std.range,
			 std.conv,
			 std.format;

debug import std.stdio;

private struct St{
	/// errors
	SmErr[] errs;
	/// root stab
	STab stabR;
	/// local STab
	STab stab;
	/// context
	IdentU[] ctx;
	/// symbols dependent on current call
	void[0][ASymbol*] dep;
	/// resulting expression
	RExpr res;
	/// parameter types if resulting expression is expected to be callable
	AValCT[] params;
	/// expected type
	OptVal!ADataType expT;
	/// if resulting expression is expected to be a ref
	bool isRefExpt = false;
	/// `RFn` for each `AFn.uid`
	RFn[string] fns;
}

private alias It = ItL!(mixin(__MODULE__), 0);

/// Verifies if return type of expression can be casted to expected type,
/// adding appropriate errors, if not, and modifying the expression to do
/// conversion if needed.
///
/// Returns: true if error-free, false if error added
pragma(inline, true)
private bool resultSet(Location pos, RExpr expr, ref St st){
	assert((st.expT.isVal * 1)
			+ ((st.params.length > 0) * 1)
			+ (st.isRefExpt * 1) <= 1);
	if (st.isRefExpt){
		if (!expr.hasType){
			st.errs ~= errExprValExpected(pos);
			return false;
		}
		if (expr.type.type != ADataType.Type.Ref &&
				expr.type.type != ADataType.Type.Fn){
			st.errs ~= errNotRef(pos);
			return false;
		}
	}
	if (!st.expT.isVal){
		if (st.params.length &&
				expr.callabilityOf(st.params, st.ctx) == size_t.max){
			st.errs ~= errCallableIncompat(pos, expr.toString,
					st.params.map!(p => p.toString));
			return false;
		}
		st.res = expr;
		return true;
	}
	if (!expr.hasType){
		st.errs ~= errExprValExpected(pos);
		return false;
	}
	if (!expr.type.canCastTo(st.expT.val, st.ctx)){
		st.errs ~= errIncompatType(pos, st.expT.val.toString, expr.type.toString);
		return false;
	}
	st.res = expr.to(st.expT.val, st.ctx).val;
	return true;
}

@ItFn @ITL(0){
	void identExprIter(IdentExpr node, ref St st){
		ASymbol* res;
		if (st.params.length){
			foreach (range; st.stabR.find(node.ident.IdentU, st.ctx)){
				size_t best = size_t.max;
				size_t count = 0;
				foreach (ASymbol* sym; range.filter!(s => s.isCallable)){
					if (!sym.isComplete){
						SmErr[] errs = symDo(sym, st.stabR, st.dep, st.fns);
						if (errs.length){
							st.errs ~= errs;
							continue;
						}
					}
					immutable size_t callability = sym.callabilityOf(st.params, st.ctx);
					if (callability == size_t.max) continue;
					if (callability == best){
						count ++;
					} else
					if (callability < best){
						best = callability;
						count = 1;
						res = sym;
					}
				}
				if (count == 0){
					st.errs ~= errUndef(node.pos, node.ident);
					return;
				}
				if (count > 1){
					st.errs ~= errCallableConflict(node.pos, node.ident,
							st.params.map!(p => p.toString));
				}
			}
		} else {
			foreach (symR; st.stabR.find(node.ident.IdentU, st.ctx)){
				auto syms = symR;
				bool found = false;
				foreach (ASymbol* s; symR){
					if (found){
						st.errs ~= errIdentAmbig(node.pos, node.ident,
								syms.map!(s => s.ident.toString));
						return;
					}
					found = true;
					res = s;
				}
				if (found)
					break;
			}
		}
		if (res is null){
			st.errs ~= errUndef(node.pos, node.ident);
			return;
		}
		if (!res.isComplete){
			SmErr[] errs = symDo(res, st.stabR, st.dep, st.fns);
			if (errs.length){
				st.errs ~= errs;
				return;
			}
		}
		// convert res to RExpr
		RExpr r;
		switch (res.type){
			case ASymbol.Type.Struct:
			case ASymbol.Type.Union:
			case ASymbol.Type.Enum:
				r = new RAValCTExpr(res.AValCT);
				r.pos = node.pos;
				break;
			case ASymbol.Type.EnumConst:
				r = new REnumConstGetExpr(AVal(res.enumCS.type, res.enumCS.data),
						&res.enumCS);
				r.pos = node.pos;
				break;
			case ASymbol.Type.Fn:
				if (st.isRefExpt){
					r = new RFnExpr(&res.fnS);
				} else
				if (res.callabilityOf([], st.ctx) != size_t.max){
					r = (&res.fnS).call(node.pos, [], st.ctx).val;
					if (RFnCallExpr fnCall = cast(RFnCallExpr)r)
						fnCall.isImplicit = true;
				} else {
					r = new RFnExpr(&res.fnS);
				}
				break;
			case ASymbol.Type.Var:
				if (st.isRefExpt){
					r = new RVarRefExpr(res.varS,
							st.ctx.length &&
							res.varS.ident.length &&
							st.ctx[0] != res.varS.ident[0] &&
							res.varS.vis == Visibility.IPub);
				} else {
					r = new RVarExpr(res.varS,
							st.ctx.length &&
							res.varS.ident.length &&
							st.ctx[0] != res.varS.ident[0] &&
							res.varS.vis == Visibility.IPub);
				}
				r.pos = node.pos;
				break;
			case ASymbol.Type.Alias:
			case ASymbol.Type.Import:
			case ASymbol.Type.Template:
				st.errs ~= errUnsup(node);
				return;
			default:
				st.errs ~= errUnsup(node.pos, res.type.to!string);
				return;
		}
		resultSet(node.pos, r, st);
	}

	void blockExprIter(BlockExpr node, ref St st){
		RBlockExpr r = new RBlockExpr;
		r.pos = node.pos;
		AutoExpr autoExpr = cast(AutoExpr)node.type;
		immutable bool isAuto = autoExpr !is null;
		if (isAuto && autoExpr.isConst){
			st.errs ~= errAutoConstIncompat(node.type.pos);
		}
		ADataType xType; {
			if (!isAuto){
				SmErrsVal!ADataType res = eval4Type(node.type, st.stabR, st.ctx,
						st.dep, st.fns);
				if (res.err){
					st.errs ~= res.err;
					return;
				}
				xType = res.val;
			}
		}

		SmErrsVal!(RStatement[]) stmnts = resolveStmnt(node.block, st.stabR, st.ctx,
				st.dep, st.fns, &xType, isAuto);
		if (stmnts.isErr){
			st.errs ~= stmnts.err;
			return;
		}
		if (stmnts.val.length){
			if (RBlock rblock = cast(RBlock)(stmnts.val[0])){
				r.block = rblock;
			} else {
				r.block = new RBlock;
				r.block.pos = node.block.pos;
				r.block.statements = stmnts.val;
			}
		}
		r.type = xType;
		resultSet(node.pos, r, st);
	}

	void commaExprIter(CommaExpr node, ref St st){
		RExpr[] exprs;
		foreach (Expression expr; node.exprs){
			SmErrsVal!RExpr exprRes = resolve(expr, st.stabR, st.ctx, st.dep,
					st.fns);
			if (exprRes.isErr){
				st.errs ~= exprRes.err;
				return;
			}
			exprs ~= exprRes.val;
		}
		RAValCTExpr r = new RAValCTExpr(
				exprs.map!(e => e.AValCT).array.flatten.AValCT);
		r.pos = node.pos;
		resultSet(node.pos, r, st);
	}

	void structAnonIter(StructAnon node, ref St st){
		immutable string name = format!"struct$_%d_%d_$"(
				node.pos.line, node.pos.col);
		ASymbol* sym = new ASymbol(AStruct(st.ctx ~ name.IdentU));
		st.stab.add(name.IdentU, sym, st.ctx);
		sym.structS.vis = Visibility.Default;
		SmErr[] errs = structDo(node.val, &sym.structS, st.stabR, st.ctx,
				st.dep, st.fns);
		if (errs.length){
			st.errs ~= errs;
			return;
		}
		sym.isComplete = true;
		RExpr r = new RAValCTExpr(ADataType.of(&sym.structS).AValCT);
		resultSet(node.pos, r, st);
	}

	void unionAnonIter(UnionAnon node, ref St st){
		immutable string name = format!"union$_%d_%d_$"(
				node.pos.line, node.pos.col);
		ASymbol* sym = new ASymbol(AUnion(st.ctx ~ name.IdentU));
		st.stab.add(name.IdentU, sym, st.ctx);
		sym.structS.vis = Visibility.Default;
		SmErr[] errs;
		if (NamedUnion sub = cast(NamedUnion)node.val){
			errs = unionNamedDo(sub, sym, st.stabR, st.ctx, st.dep, st.fns);
		} else
		if (UnnamedUnion sub = cast(UnnamedUnion)node.val){
			errs = unionUnnamedDo(sub, sym, st.stabR, st.ctx, st.dep, st.fns);
		}
		if (errs.length){
			st.errs ~= errs;
			return;
		}
		sym.isComplete = true;
		RExpr r = new RAValCTExpr(ADataType.of(&sym.unionS).AValCT);
		resultSet(node.pos, r, st);
	}

	void fnAnonExprIter(FnAnonExpr node, ref St st){
		immutable string name = format!"fn$_%d_%d_$"(node.pos.line, node.pos.col);
		ASymbol* sym = new ASymbol(AFn(st.ctx ~ name.IdentU));
		AFn* symC = &sym.fnS;
		symC.vis = Visibility.Default;
		symC.uid = format!"%s.%s"(st.ctx.toString, name);
		symC.isAlisFn = true;

		void[0][string] nameSet;
		foreach (size_t i, FParam param; node.params.params){
			if (param.name != "_" && param.name in nameSet){
				st.errs ~= errIdentReuse(param.pos, param.name);
				continue;
			}
			nameSet[param.name] = (void[0]).init;
			AutoExpr autoExpr = cast(AutoExpr)param.type;
			immutable bool isAuto =
				autoExpr !is null || param.type is null;
			ADataType type;
			if (!isAuto){
				SmErrsVal!ADataType typeRes = eval4Type(param.type, st.stabR, st.ctx,
						st.dep, st.fns);
				if (typeRes.isErr)
					st.errs ~= typeRes.err;
				type = typeRes.val;
			}
			if (param.val !is null){
				st.errs ~= errFnAnonParamDef(param.pos, param.name);
				continue;
			}
			if (isAuto){
				st.errs ~= errUnsup(param.pos,
						"inferring type for anonymous function params");
				continue;
			}
			symC.paramsV ~= OptVal!(void[])();
			symC.paramsN ~= param.name;
			symC.paramsT ~= type;
		}
		RFn r = new RFn;
		r.pos = node.pos;
		r.ident = symC.ident.toString;
		r.paramsT = symC.paramsT;
		r.paramsN = symC.paramsN;
		st.fns[symC.uid] = r;
		st.stab.add(name.IdentU, sym, st.ctx);
		RExpr res = new RFnExpr(symC);

		string encodedName = symC.ident[$ - 1].toString.fnNameEncode(symC.paramsT);
		STab subSt = new STab;
		foreach (size_t i; 0 .. symC.paramsN.length){
			ASymbol* param = new ASymbol(
					AVar(st.ctx ~ encodedName.IdentU ~ symC.paramsN[i].IdentU,
						symC.paramsT[i], symC.paramsV[i]));
			param.varS.uid = param.ident.toString;
			param.isComplete = true;
			subSt.add(symC.paramsN[i].IdentU, param, param.ident[0 .. 1]);
		}
		st.stab.add(encodedName.IdentU, subSt, symC.vis, st.ctx);
		SmErrsVal!RExpr exprRes = resolve(node.body, st.stabR,
				st.ctx ~ encodedName.IdentU, st.dep, st.fns);
		if (exprRes.isErr){
			st.errs ~= exprRes.err;
			return;
		}
		r.body = exprRes.val;
		symC.retT = r.body.type;
		sym.isComplete = true;
		resultSet(node.pos, res, st);
	}

	void structLiteralExprIter(StructLiteralExpr node, ref St st){
		void[0][string] nameSet;
		string[] names;
		RExpr[] vals;
		foreach (KeyVal kv; node.keyVals){
			if (kv.key in nameSet){
				st.errs ~= errIdentReuse(kv.pos, kv.key);
				continue;
			}
			nameSet[kv.key] = (void[0]).init;
			SmErrsVal!RExpr exprRes = resolve(kv.val, st.stabR, st.ctx, st.dep,
					st.fns);
			if (exprRes.isErr){
				st.errs ~= exprRes.err;
				continue;
			}
			names ~= kv.key;
			vals ~= exprRes.val;
		}
		ASymbol* sym = new ASymbol(AStruct());
		AStruct* symC = &(sym.structS);
		foreach (size_t i, string name; names){
			symC.names[name] = i;
			symC.nameVis[name] = Visibility.Pub;
		}
		symC.initD = vals.length.iota.map!(i => OptVal!(void[])()).array;
		symC.types = vals.map!(v => v.type).array;
		symC.vis = Visibility.Pub;
		IdentU id = format!"struct$_%d_%d_$"(node.pos.line, node.pos.col).IdentU;
		symC.ident = st.ctx ~ id;
		sym.isComplete = true;
		assert (symC.isUnique == false);
		st.stab.add(id, sym, [IdentU.init]);
		RStructLiteralExpr r = new RStructLiteralExpr(names, vals, symC);
		r.pos = node.pos;
		resultSet(node.pos, r, st);
	}

	void boolLiteralExprIter(BoolLiteralExpr node, ref St st){
		RLiteralExpr r = new RLiteralExpr(node.val.AVal);
		r.pos = node.pos;
		resultSet(node.pos, r, st);
	}

	void literalIntExprIter(LiteralIntExpr node, ref St st){
		RLiteralExpr r = new RLiteralExpr(node.val.AVal);
		r.pos = node.pos;
		resultSet(node.pos, r, st);
	}

	void literalFloatExprIter(LiteralFloatExpr node, ref St st){
		RLiteralExpr r = new RLiteralExpr(node.val.AVal);
		r.pos = node.pos;
		resultSet(node.pos, r, st);
	}

	void literalStringExprIter(LiteralStringExpr node, ref St st){
		RLiteralExpr r = new RLiteralExpr((cast(string)node.val.dup).AVal);
		r.pos = node.pos;
		resultSet(node.pos, r, st);
	}

	void literalCharExprIter(LiteralCharExpr node, ref St st){
		RLiteralExpr r = new RLiteralExpr(node.val.AVal);
		r.pos = node.pos;
		resultSet(node.pos, r, st);
	}

	void literalArrayExprIter(LiteralArrayExpr node, ref St st){
		RExpr[] elements;
		foreach (Expression elem; node.elements){
			SmErrsVal!RExpr exprRes = resolve(elem, st.stabR, st.ctx, st.dep,
					st.fns);
			if (exprRes.isErr){
				st.errs ~= exprRes.err;
				return;
			}
			elements ~= exprRes.val;
		}
		RArrayLiteralExpr r = new RArrayLiteralExpr(elements);
		r.pos = node.pos;
		resultSet(node.pos, r, st);
	}

	void autoExprIter(AutoExpr node, ref St st){
		st.errs ~= errUnsup(node); // what even is `auto` doing here
	}

	void thisExprIter(ThisExpr node, ref St st){
		st.errs ~= errUnsup(node.pos, "`this` as expression");
	}

	void intExprIter(IntExpr node, ref St st){
		RAValCTExpr r = new RAValCTExpr;
		r.pos = node.pos;
		r.res = ADataType.ofInt.AValCT;
		resultSet(node.pos, r, st);
	}

	void uIntExprIter(UIntExpr node, ref St st){
		RAValCTExpr r = new RAValCTExpr;
		r.pos = node.pos;
		r.res = ADataType.ofUInt.AValCT;
		resultSet(node.pos, r, st);
	}

	void floatExprIter(FloatExpr node, ref St st){
		RAValCTExpr r = new RAValCTExpr;
		r.pos = node.pos;
		r.res = ADataType.ofFloat.AValCT;
		resultSet(node.pos, r, st);
	}

	void charExprIter(CharExpr node, ref St st){
		RAValCTExpr r = new RAValCTExpr;
		r.pos = node.pos;
		r.res = ADataType.ofChar.AValCT;
		resultSet(node.pos, r, st);
	}

	void stringExprIter(StringExpr node, ref St st){
		RAValCTExpr r = new RAValCTExpr;
		r.pos = node.pos;
		r.res = ADataType.ofString.AValCT;
		resultSet(node.pos, r, st);
	}

	void boolExprIter(BoolExpr node, ref St st){
		RAValCTExpr r = new RAValCTExpr;
		r.pos = node.pos;
		r.res = ADataType.ofBool.AValCT;
		resultSet(node.pos, r, st);
	}

	void opPostExprOverridableIter(OpPostExprOverridable node, ref St st){
		OpCallExpr call = new OpCallExpr;
		call.pos = node.pos;
		IdentExpr callee = new IdentExpr;
		callee.pos = node.pos;
		callee.ident = "opPost";
		call.callee = callee;
		LiteralStringExpr op = new LiteralStringExpr;
		op.pos = node.pos;
		op.val = node.op;
		call.params = [op, node.operand];
		opCallExprIter(call, st);
	}

	void opPreExprOverridableIter(OpPreExprOverridable node, ref St st){
		OpCallExpr call = new OpCallExpr;
		call.pos = node.pos;
		IdentExpr callee = new IdentExpr;
		callee.pos = node.pos;
		callee.ident = "opPre";
		call.callee = callee;
		LiteralStringExpr op = new LiteralStringExpr;
		op.pos = node.pos;
		op.val = node.op;
		call.params = [op, node.operand];
		opCallExprIter(call, st);
	}

	void opBinExprOverridableIter(OpBinExprOverridable node, ref St st){
		OpCallExpr call = new OpCallExpr;
		call.pos = node.pos;
		IdentExpr callee = new IdentExpr;
		callee.pos = node.pos;
		callee.ident = "opBin";
		call.callee = callee;
		LiteralStringExpr op = new LiteralStringExpr;
		op.pos = node.pos;
		op.val = node.op;
		call.params = [op, node.lhs, node.rhs];
		opCallExprIter(call, st);
	}

	void intrinsicExprIter(IntrinsicExpr node, ref St st){
		if (!node.name.isIntrN){
			st.errs ~= errIntrUnk(node.pos, node.name);
			return;
		}
		if (callabilityOf(node.name, st.params, st.ctx) == size_t.max){
			st.errs ~= errCallableIncompat(node.pos, node.name.format!"$%s",
					st.params.map!(p => p.toString));
			return;
		}
		if (st.params.length){
			RIntrinsicPartCallExpr r = new RIntrinsicPartCallExpr;
			r.pos = node.pos;
			r.name = node.name;
			st.res = r;
			return;
		}
		SmErrsVal!RExpr res = resolveIntrN(node.name, node.pos, st.params,
				st.stabR, st.ctx, st.dep, st.fns);
		if (res.isErr){
			st.errs ~= res.err;
			return;
		}
		resultSet(node.pos, res.val, st);
	}

	void opCallExprIter(OpCallExpr node, ref St st){
		AValCT[] params;
		RExpr[] paramsExpr;
		foreach (Expression p; node.params){
			SmErrsVal!RExpr exprRes = resolve(p, st.stabR, st.ctx, st.dep, st.fns);
			if (exprRes.isErr){
				st.errs ~= exprRes.err;
				continue;
			}
			paramsExpr ~= exprRes.val;
			SmErrsVal!AValCT pRes = eval(paramsExpr[$ - 1], st.stabR, st.ctx);
			if (pRes.isErr){
				st.errs ~= pRes.err;
				continue;
			}
			params ~= pRes.val;
		}
		if (params.length != node.params.length) return;
		params = params.flatten;
		RExpr callee; {
			SmErrsVal!RExpr calleeRes = resolve(node.callee, st.stabR, st.ctx,
					st.dep, st.fns, params);
			if (calleeRes.isErr){
				st.errs ~= calleeRes.err;
				return;
			}
			callee = calleeRes.val;
		}

		RExpr r;
		if (RPartCallExpr pFnCall = cast(RPartCallExpr)callee){
			SmErrsVal!RExpr res = pFnCall.callee.call(pFnCall.pos,
					pFnCall.params ~ params, st.ctx);
			if (res.isErr){
				st.errs ~= res.err;
				return;
			}
			r = res.val;
		} else
		if (RTmPartInitExpr pTmCall = cast(RTmPartInitExpr)callee){
			st.errs ~= errUnsup(node.pos, "Template instantiation");
			// add node.params to pTmCall.tparams
			// if st.params, result should be callable with st.params:
			// pTmCall(.., node.params)(st.params)
			r = pTmCall;
		} else
		if (RIntrinsicPartCallExpr iCall = cast(RIntrinsicPartCallExpr)callee){
			iCall.params ~= params;
			SmErrsVal!RExpr res = resolveIntrN(iCall.name, iCall.pos, iCall.params,
					st.stabR, st.ctx, st.dep, st.fns);
			if (res.isErr){
				st.errs ~= res.err;
				return;
			}
			st.res = res.val;
			return;
		} else {
			if (RFnCallExpr fnCall = cast(RFnCallExpr)callee){
				if (fnCall.isImplicit){
					fnCall.isImplicit = false;
					resultSet(node.pos, fnCall, st);
					return;
				}
			}
			SmErrsVal!RExpr res = callee.call(node.pos, params, st.ctx);
			if (res.isErr){
				st.errs ~= res.err;
				return;
			}
			r = res.val;
		}
		resultSet(node.pos, r, st);
	}

	void opDotBinIter(OpDotBin node, ref St st){
		bool lhsIsSeq = false;
		AValCT[] lhs; {
			SmErrsVal!AValCT lhsRes = eval(node.lhs, st.stabR, st.ctx,
					st.dep, st.fns);
			if (lhsRes.isErr){
				st.errs ~= lhsRes.err;
				return;
			}
			lhsIsSeq = lhsRes.val.type == AValCT.Type.Seq;
			lhs = lhsRes.val.flatten;
		}
		SmErr[] errs;
		if (!lhsIsSeq){
			if (IdentExpr rhsId = cast(IdentExpr)node.rhs){
				AValCT[] params = [lhs[0], rhsId.ident.AVal.AValCT];
				if (IntrN.Member.callabilityOf(params, st.ctx) != size_t.max){
					SmErrsVal!RExpr res = IntrN.Member.resolveIntrN(node.pos, params,
							st.stabR, st.ctx, st.dep, st.fns);
					if (res.isErr){
						errs = res.err;
					} else {
						RExpr r = res.val;
						if (r.hasType && !st.isRefExpt && r.type.type == ADataType.Type.Ref){
							r = new RDerefExpr(r);
							r.pos = (cast(RDerefExpr)r).val.pos;
						}
						resultSet(node.pos, r, st);
						return;
					}
				}
			}
		}

		AValCT[] pTypes = lhs ~ st.params;

		// rhs is intrinsic
		if (IntrinsicExpr intr = cast(IntrinsicExpr)node.rhs){
			if (st.params && intr.name.callabilityOf(pTypes, st.ctx) != size_t.max){
				RIntrinsicPartCallExpr r = new RIntrinsicPartCallExpr;
				r.pos = intr.pos;
				r.name = intr.name;
				r.params = lhs;
				if (st.expT.isVal){
					assert (false,
							"cannot expect data type from partial intrinsic call");
				}
				st.res = r;
				return;
			} else
			if (intr.name.callabilityOf(lhs, st.ctx) != size_t.max){
				RExpr r; {
					SmErrsVal!RExpr res = resolveIntrN(intr.name, intr.pos, lhs,
							st.stabR, st.ctx, st.dep, st.fns);
					if (res.isErr){
						st.errs ~= res.err;
						return;
					}
					r = res.val;
				}
				resultSet(node.pos, r, st);
				return;
			}
			st.errs ~= errCallableIncompat(intr.pos, intr.name.format!"$%s",
					pTypes.map!(p => p.toString));
			st.errs ~= errCallableIncompat(intr.pos, intr.name.format!"$%s",
					lhs.map!(p => p.toString));
			return;
		}

		RExpr r; {
			SmErrsVal!RExpr res = resolve(node.rhs, st.stabR, st.ctx, st.dep,
					st.fns, pTypes);
			if (res.isErr){
				errs = res.err;
				res = resolve(node.rhs, st.stabR, st.ctx, st.dep, st.fns, lhs);
				if (res.isErr){
					st.errs ~= errs;
					st.errs ~= res.err;
					return;
				}
				res = res.val.call(node.pos, lhs, st.ctx);
				if (res.isErr){
					st.errs ~= res.err;
					return;
				}
				r = res.val;
				resultSet(node.pos, r, st);
				return;
			}
			// partial
			r = res.val;
		}

		RPartCallExpr pCall = new RPartCallExpr;
		pCall.pos = node.pos;
		pCall.callee = r;
		pCall.params = lhs;
		if (st.params.length == 0){
			SmErrsVal!RExpr res = pCall.callee.call(node.pos, pCall.params, st.ctx);
			if (res.isErr){
				st.errs = res.err;
				return;
			}
			if (RFnCallExpr fnCall = cast(RFnCallExpr)res.val)
				fnCall.isImplicit = true;
			resultSet(node.pos, res.val, st);
			return;
		}
		st.res = pCall;
		if (st.expT.isVal){
			debug stderr.writeln("st.isExpT in partial call!");
			assert (false,
					"cannot expect data type from partial call");
		}
	}

	void opIndexExprIter(OpIndexExpr node, ref St st){
		RExpr sub; {
			SmErrsVal!RExpr subRes = resolve(node.lhs, st.stabR, st.ctx, st.dep,
					st.fns);
			if (subRes.isErr){
				st.errs ~= subRes.err;
				return;
			}
			sub = subRes.val;
		}
		AValCT subVal; {
			SmErrsVal!AValCT subValRes = eval(sub, st.stabR, st.ctx);
			if (subValRes.isErr){
				st.errs ~= subValRes.err;
				return;
			}
			subVal = subValRes.val;
		}

		if (sub.type.type == ADataType.Type.Seq){
			if (node.indexes.length != 1){
				st.errs ~= errParamCount(node.pos, "index", 1, node.indexes.length);
				return;
			}
			AValCT ind; {
				SmErrsVal!AValCT indRes = eval(node.indexes[0], st.stabR, st.ctx,
						st.dep, st.fns);
				if (indRes.isErr){
					st.errs ~= indRes.err;
					return;
				}
				ind = indRes.val;
			}
			if (ind.type != AValCT.Type.Literal){
				st.errs ~= errIncompatType(node.indexes[0].pos, "uint literal",
						ind.toString);
				return;
			}
			if (!ind.val.canCastTo(ADataType.ofUInt)){
				st.errs ~= errIncompatType(node.indexes[0].pos, "uint",
						ind.val.type.toString);
				return;
			}
			if (subVal.type != AValCT.Type.Seq){
				st.errs ~= errIncompatType(node.lhs.pos, "sequence", sub.toString);
				return;
			}
			ind = ind.to(ADataType.ofUInt).val;
			size_t indI = ind.val.data.as!size_t;
			if (indI >= subVal.seq.length){
				st.errs ~= errBounds(node.indexes[0].pos, subVal.seq.length, indI);
				return;
			}
			RExpr r = subVal.seq[indI].toRExpr;
			r.pos = node.pos;
			resultSet(node.pos, r, st);
			return;
		}

		RExpr[] params;
		ADataType[] paramsT;
		foreach (Expression index; node.indexes){
			SmErrsVal!RExpr exprRes = resolve(index, st.stabR, st.ctx, st.dep,
					st.fns);
			if (exprRes.isErr){
				st.errs ~= exprRes.err;
				continue;
			}
			params ~= exprRes.val;
			paramsT ~= exprRes.val.type;
		}
		if (params.length != node.indexes.length ||
				params.length != paramsT.length)
			return;

		if ((sub.type.type == ADataType.Type.Array ||
					sub.type.type == ADataType.Type.Slice) &&
				node.indexes.length == 1 &&
				paramsT[0].canCastTo(ADataType.ofUInt)){
			SmErrsVal!AValCT paramVal = eval(params[0], st.stabR, st.ctx);
			if (paramVal.isErr){
				st.errs ~= paramVal.err;
				return;
			}
			if (callabilityOf(IntrN.ArrayInd, [subVal, paramVal.val],
						st.ctx) == size_t.max){
				st.errs ~= errCallableIncompat(node.pos, IntrN.ArrayInd.format!"$%s",
						[subVal, paramVal.val].map!(p => p.toString));
				return;
			}
			SmErrsVal!RExpr res = resolveIntrN(IntrN.ArrayInd, node.pos,
					[subVal, paramVal.val],
					st.stabR, st.ctx, st.dep, st.fns);
			if (res.isErr){
				st.errs ~= res.err;
				return;
			}
			resultSet(node.pos, res.val, st);
			return;
		}

		OpCallExpr call = new OpCallExpr;
		call.pos = node.pos;
		IdentExpr callee = new IdentExpr;
		callee.pos = node.pos;
		callee.ident = "opIndex";
		call.callee = callee;
		call.params = node.lhs ~ node.indexes;
		opCallExprIter(call, st);
	}

	void opAssignBinIter(OpAssignBin node, ref St st){
		RExpr lhs; {
			SmErrsVal!RExpr res = resolve4Ref(node.lhs, st.stabR, st.ctx,
					st.dep, st.fns);
			if (res.isErr){
				st.errs ~= res.err;
				return;
			}
			lhs = res.val;
		}
		if (!lhs.hasType){
			st.errs ~= errExprValExpected(node.lhs.pos);
			return;
		}
		if (lhs.type.type != ADataType.Type.Ref){
			st.errs ~= errNotRef(node.lhs.pos);
			return;
		}
		ADataType expectedType = *(lhs.type.refT);
		if (expectedType.isConst){
			st.errs ~= errAssignConst(node.pos, expectedType.toString);
			return;
		}
		if (expectedType.type == ADataType.Type.Ref){
			st.errs ~= errAssignRef(node.pos);
			return;
		}
		RExpr rhs; {
			SmErrsVal!RExpr res = resolve(node.rhs, st.stabR, st.ctx,
					st.dep, st.fns);
			if (res.isErr){
				st.errs ~= res.err;
				return;
			}
			rhs = res.val;
		}
		if (!rhs.hasType){
			st.errs ~= errExprValExpected(node.rhs.pos);
			return;
		}
		if (!rhs.type.canCastTo(expectedType, st.ctx)){
			st.errs ~= errIncompatType(node.pos, expectedType.toString,
					rhs.type.toString);
			return;
		}
		SmErrsVal!RExpr rhsConverted = rhs.to(expectedType, st.ctx).val;
		if (rhsConverted.isErr){
			st.errs ~= rhsConverted.err;
			return;
		}
		RAssignExpr r = new RAssignExpr();
		r.refExpr = lhs;
		r.valExpr = rhsConverted.val;
		r.pos = node.pos;
		resultSet(node.pos, r, st);
	}

	void opRefPostIter(OpRefPost node, ref St st){
		RExpr sub; {
			SmErrsVal!RExpr res = resolve(node.operand, st.stabR, st.ctx,
					st.dep, st.fns);
			if (res.isErr){
				st.errs ~= res.err;
				return;
			}
			sub = res.val;
		}
		if (!sub.hasType){
			st.errs ~= errExprValExpected(node.operand.pos);
			return;
		}
		if (sub.type.type != ADataType.Type.Ref){
			st.errs ~= errDerefNoRef(node.pos, sub.type.toString);
			return;
		}
		RDerefExpr r = new RDerefExpr(sub);
		r.pos = node.pos;
		resultSet(node.pos, r, st);
	}

	void opDotsPostIter(OpDotsPost node, ref St st){
		st.errs ~= errUnsup(node);
	}

	void opIsPreIter(OpIsPre node, ref St st){
		IntrinsicExpr itr = new IntrinsicExpr;
		itr.pos = node.pos;
		itr.name = IntrN.UnionIs;
		OpCallExpr call = new OpCallExpr;
		call.pos = node.pos;
		call.callee = itr;
		call.params = [node.operand];
		opCallExprIter(call, st);
	}

	void opNotIsPreIter(OpNotIsPre node, ref St st){
		IntrinsicExpr itr = new IntrinsicExpr;
		itr.pos = node.pos;
		itr.name = IntrN.Not;
		OpCallExpr itrCall = new OpCallExpr;
		itrCall.pos = node.pos;
		itrCall.callee = itr;
		IntrinsicExpr isItr = new IntrinsicExpr;
		isItr.pos = node.pos;
		isItr.name = IntrN.UnionIs;
		OpCallExpr isCall = new OpCallExpr;
		isCall.pos = node.pos;
		isCall.callee = isItr;
		isCall.params = [node.operand];
		itrCall.params = [isCall];
		opCallExprIter(itrCall, st);
	}

	void opConstPreIter(OpConstPre node, ref St st){
		ADataType type; {
			SmErrsVal!ADataType typeRes = eval4Type(node.operand, st.stabR, st.ctx,
					st.dep, st.fns);
			if (typeRes.isErr){
				st.errs ~= typeRes.err;
				return;
			}
			type = typeRes.val;
		}
		if (type.isConst){
			st.errs ~= errConstConst(node.pos, type.toString);
			return;
		}
		RAValCTExpr r = new RAValCTExpr(type.constOf.AValCT);
		r.pos = node.pos;
		resultSet(node.pos, r, st);
	}

	void opRefPreIter(OpRefPre node, ref St st){
		if (FnAnonExpr fnExpr = cast(FnAnonExpr)node.operand){
			ADataType retType; {
				SmErrsVal!ADataType res = eval4Type(fnExpr.body, st.stab, st.ctx,
						st.dep, st.fns);
				if (res.isErr){
					st.errs ~= res.err;
					return;
				}
				retType = res.val;
			}
			ADataType[] paramTypes;
			if (fnExpr.params){
				foreach (FParam param; fnExpr.params.params){
					if (param.type is null){
						st.errs ~= errExprTypeExpected(param.pos);
						continue;
					}
					SmErrsVal!ADataType res = eval4Type(param.type, st.stab, st.ctx,
							st.dep, st.fns);
					if (res.isErr){
						st.errs ~= res.err;
						continue;
					}
					paramTypes ~= res.val;
				}
				if (paramTypes.length != fnExpr.params.params.length)
					return;
			}
			RAValCTExpr res = new RAValCTExpr(
					ADataType.ofFn(retType, paramTypes).AValCT);
			res.pos = node.pos;
			if (st.isRefExpt){
				st.errs ~= errRefNonRefable(node.pos, res.res.toString);
				return;
			}
			resultSet(node.pos, res, st);
			return;
		}

		SmErrsVal!RExpr res = resolve4Ref(node.operand, st.stabR, st.ctx,
				st.dep, st.fns);
		SmErr[] errs;
		if (res.isErr){
			errs ~= res.err;
			res = resolve(node.operand, st.stabR, st.ctx, st.dep, st.fns);
			if (res.isErr){
				st.errs ~= errs;
				st.errs ~= res.err;
				return;
			}
			if (RAValCTExpr valExpr = cast(RAValCTExpr)(res.val)){
				if (!valExpr.res.isVal){
					st.errs ~= errRefNonRefable(node.pos, valExpr.res.toString);
					return;
				}
				OptVal!ADataType typeRes = valExpr.res.asType;
				if (!typeRes.isVal){
					st.errs ~= errRefNonRefable(node.pos, valExpr.res.toString);
					return;
				}
				RAValCTExpr type = new RAValCTExpr(ADataType.ofRef(typeRes.val).AValCT);
				type.pos = node.pos;
				if (st.isRefExpt){
					st.errs ~= errRefNonRefable(node.pos, type.toString);
					return;
				}
				resultSet(node.pos, type, st);
				return;
			}
		}
		RExpr expr = res.val;
		if (!expr.hasType){
			st.errs ~= errExprValExpected(node.operand.pos);
			return;
		}
		if (expr.type.type != ADataType.Type.Ref &&
				expr.type.type != ADataType.Type.Fn){
			st.errs ~= errNotRef(node.pos);
			return;
		}
		if (st.isRefExpt){
			st.errs ~= errRefNonRefable(node.pos, expr.toString);
			return;
		}
		resultSet(node.pos, expr, st);
	}

	void opTagPreIter(OpTagPre node, ref St st){
		st.errs ~= errUnsup(node.pos, "`#` operator in expressions");
	}

	void opArrowBinIter(OpArrowBin node, ref St st){
		st.errs ~= errUnsup(node.pos, "`->` operator in expression");
	}

	void opCommaBinIter(OpCommaBin node, ref St st){
		st.errs ~= errUnxp(node.pos, "OpCommaBin should not have happened");
	}

	void opColonBinIter(OpColonBin node, ref St st){
		ADataType lhs; {
			SmErrsVal!ADataType res = eval4Type(node.lhs, st.stabR, st.ctx,
					st.dep, st.fns);
			if (res.isErr){
				st.errs ~= res.err;
				return;
			}
			lhs = res.val;
		}
		ADataType rhs; {
			SmErrsVal!ADataType res = eval4Type(node.rhs, st.stabR, st.ctx,
					st.dep, st.fns);
			if (res.isErr){
				st.errs ~= res.err;
				return;
			}
			rhs = res.val;
		}
		AValCT val;
		if (lhs.canCastTo(rhs, st.ctx)){
			val = true.AVal.AValCT;
		} else {
			val = false.AVal.AValCT;
		}
		RAValCTExpr r = new RAValCTExpr(val);
		r.pos = node.pos;
		resultSet(node.pos, r, st);
	}

	void opIsBinIter(OpIsBin node, ref St st){
		IntrinsicExpr itr = new IntrinsicExpr;
		itr.pos = node.pos;
		itr.name = IntrN.Is;
		OpCallExpr call = new OpCallExpr;
		call.pos = node.pos;
		call.callee = itr;
		call.params = [node.lhs, node.rhs];
		opCallExprIter(call, st);
	}

	void opNotIsBinIter(OpNotIsBin node, ref St st){
		IntrinsicExpr itr = new IntrinsicExpr;
		itr.pos = node.pos;
		itr.name = IntrN.IsNot;
		OpCallExpr call = new OpCallExpr;
		call.pos = node.pos;
		call.callee = itr;
		call.params = [node.lhs, node.rhs];
		opCallExprIter(call, st);
	}

	void opAndBin(OpAndBin node, ref St st){
		RExpr lhs; {
			SmErrsVal!RExpr res = resolve(node.lhs, st.stabR, st.ctx,
					st.dep, st.fns);
			if (res.isErr){
				st.errs ~= res.err;
				return;
			}
			lhs = res.val;
		}
		RExpr rhs; {
			SmErrsVal!RExpr res = resolve(node.rhs, st.stabR, st.ctx,
					st.dep, st.fns);
			if (res.isErr){
				st.errs ~= res.err;
				return;
			}
			rhs = res.val;
		}
		if (!lhs.type.canCastTo(ADataType.ofBool, st.ctx)){
			st.errs ~= errIncompatType(node.lhs.pos, ADataType.ofBool.toString,
					lhs.type.toString);
			return;
		}
		if (!rhs.type.canCastTo(ADataType.ofBool, st.ctx)){
			st.errs ~= errIncompatType(node.rhs.pos, ADataType.ofBool.toString,
					rhs.type.toString);
			return;
		}
		RAndExpr ret = new RAndExpr(
				lhs.to(ADataType.ofBool, st.ctx).val,
				rhs.to(ADataType.ofBool, st.ctx).val);
		ret.pos = node.pos;
		resultSet(node.pos, ret, st);
	}

	void opOrBin(OpOrBin node, ref St st){
		RExpr lhs; {
			SmErrsVal!RExpr res = resolve(node.lhs, st.stabR, st.ctx,
					st.dep, st.fns);
			if (res.isErr){
				st.errs ~= res.err;
				return;
			}
			lhs = res.val;
		}
		RExpr rhs; {
			SmErrsVal!RExpr res = resolve(node.rhs, st.stabR, st.ctx,
					st.dep, st.fns);
			if (res.isErr){
				st.errs ~= res.err;
				return;
			}
			rhs = res.val;
		}
		if (!lhs.type.canCastTo(ADataType.ofBool, st.ctx)){
			st.errs ~= errIncompatType(node.lhs.pos, ADataType.ofBool.toString,
					lhs.type.toString);
			return;
		}
		if (!rhs.type.canCastTo(ADataType.ofBool, st.ctx)){
			st.errs ~= errIncompatType(node.rhs.pos, ADataType.ofBool.toString,
					rhs.type.toString);
			return;
		}
		ROrExpr ret = new ROrExpr(
				lhs.to(ADataType.ofBool, st.ctx).val,
				rhs.to(ADataType.ofBool, st.ctx).val);
		ret.pos = node.pos;
		resultSet(node.pos, ret, st);
	}

	void opQPostIter(OpQPost node, ref St st){
		st.errs ~= errUnsup(node.pos, "error handling"); // TODO: implement
	}

	void opQQBinIter(OpQQBin node, ref St st){
		st.errs ~= errUnsup(node.pos, "error handling"); // TODO: implement
	}
}

/// Resolves Expression to RExpr
/// Params:
/// - `expr` - The expression to resolve
/// - `stab` - The root level Symbol Table
/// - `ctx` - Context where the `expr` occurs
/// - `params` - Ensure result is callable with `params`
/// Returns: RExpr or SmErr[]
pragma(inline, true)
package SmErrsVal!RExpr resolve(Expression expr, STab stabR, IdentU[] ctx,
		void[0][ASymbol*] dep, RFn[string] fns, AValCT[] params){
	assert (fns);
	St st;
	st.dep = dep;
	st.ctx = ctx.dup;
	st.stabR = stabR;
	st.stab = stabR.findSt(ctx, ctx);
	st.fns = fns;
	st.params = params.flatten;
	It.exec(expr, st);
	if (st.errs.length)
		return SmErrsVal!RExpr(st.errs);
	if (st.res is null)
		return SmErrsVal!RExpr([errUnxp(expr.pos, "resolve expr -> null")]);
	return SmErrsVal!RExpr(st.res);
}

/// Resolves Expression to RExpr
/// Params:
/// - `expr` - The expression to resolve
/// - `stab` - The root level Symbol Table
/// - `ctx` - Context where the `expr` occurs
/// - `expT` - Expected Data Type for resulting expression
/// Returns: RExpr or SmErr[]
pragma(inline, true)
package SmErrsVal!RExpr resolve(Expression expr, STab stabR, IdentU[] ctx,
		void[0][ASymbol*] dep, RFn[string] fns, ADataType expT){
	assert (fns);
	St st;
	st.dep = dep;
	st.ctx = ctx.dup;
	st.stabR = stabR;
	st.stab = stabR.findSt(ctx, ctx);
	st.fns = fns;
	st.expT = expT.OptVal!ADataType;
	It.exec(expr, st);
	if (st.errs.length)
		return SmErrsVal!RExpr(st.errs);
	if (st.res is null)
		return SmErrsVal!RExpr([errUnxp(expr.pos, "resolve expr -> null")]);
	return SmErrsVal!RExpr(st.res);
}

/// Resolves Expression to RExpr
/// Params:
/// - `expr` - The expression to resolve
/// - `stab` - The root level Symbol Table
/// - `ctx` - Context where the `expr` occurs
/// Returns: RExpr or SmErr[]
pragma(inline, true)
package SmErrsVal!RExpr resolve(Expression expr, STab stabR, IdentU[] ctx,
		void[0][ASymbol*] dep, RFn[string] fns){
	assert (fns);
	St st;
	st.dep = dep;
	st.ctx = ctx.dup;
	st.stabR = stabR;
	st.stab = stabR.findSt(ctx, ctx);
	st.fns = fns;
	It.exec(expr, st);
	if (st.errs.length)
		return SmErrsVal!RExpr(st.errs);
	if (st.res is null)
		return SmErrsVal!RExpr([errUnxp(expr.pos, "resolve expr -> null")]);
	return SmErrsVal!RExpr(st.res);
}

/// Resolves Expression to RExpr, to a reference
/// Params:
/// - `expr` - The expression to resolve
/// - `stab` - The root level Symbol Table
/// - `ctx` - Context where the `expr` occurs
/// Returns: RExpr or SmErr[]
pragma(inline, true)
package SmErrsVal!RExpr resolve4Ref(Expression expr, STab stabR, IdentU[] ctx,
		void[0][ASymbol*] dep, RFn[string] fns){
	assert (fns);
	St st;
	st.dep = dep;
	st.ctx = ctx.dup;
	st.stabR = stabR;
	st.stab = stabR.findSt(ctx, ctx);
	st.fns = fns;
	st.isRefExpt = true;
	It.exec(expr, st);
	if (st.errs.length)
		return SmErrsVal!RExpr(st.errs);
	if (st.res is null)
		return SmErrsVal!RExpr([errUnxp(expr.pos, "resolve expr -> null")]);
	return SmErrsVal!RExpr(st.res);
}

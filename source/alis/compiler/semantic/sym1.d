/++
Symbols Resolution, Level 1
+/
module alis.compiler.semantic.sym1;

import std.algorithm,
			 std.typecons,
			 std.range,
			 std.traits,
			 std.format,
			 std.meta;

import utils.ds;

debug import std.stdio;

import alis.common,
			 alis.compiler.common,
			 alis.compiler.semantic.common,
			 alis.compiler.semantic.error,
			 alis.compiler.semantic.expr,
			 alis.compiler.semantic.eval,
			 alis.compiler.semantic.types,
			 alis.compiler.ast,
			 alis.compiler.ast.iter,
			 alis.compiler.ast.rst;

import meta;

private alias It = ItL!(mixin(__MODULE__), 1);

private struct St1{
	/// errors
	SmErr[] errs;
	/// symbol table root
	STab stabR;
	/// symbol table, local
	STab stab;
	/// current context
	IdentU[] ctx;
	/// Symbol ASTNode to ASymbol* in STab mapping
	ASymbol*[ASTNode] sMap;
	/// set of symbols dependent on current call
	void[0][ASymbol*] dep;
	/// RExpr for each `AUTest.uid`
	RExpr[string] testExprs;
	/// `RFn` for each `AFn.uid`
	RFn[string] fns;
	/// initialization expression
	RExpr[ASymbol*] initers;
}

/// Checks for recursive dependecy before processing an ASTNode
/// Returns: true if recursive dependecy will happen after an ASTNode
private bool isRecDep(ASTNode node, ref St1 st){
	if (node !in st.sMap || st.sMap[node] !in st.dep)
		return false;
	st.errs ~= errRecDep(node.pos, st.sMap[node].ident.toString);
	return true;
}

@ItFn @ITL(1){
	void modIter(Module node, ref St1 st){
		STab pSt = st.stab;
		st.stab = st.stab.next[node.ident.IdentU].val;
		st.ctx ~= node.ident.IdentU;
		It.descend(node, st);
		st.stab = pSt;
		st.ctx.length --;
	}

	void fnIter(FnDef node, ref St1 st){
		if (isRecDep(node, st))
			return;
		ASymbol* sym = st.sMap[node];
		assert (sym);
		if (sym.isComplete) return;
		st.dep[sym] = (void[0]).init;
		scope(exit) st.dep.remove(sym);
		scope(exit) sym.isComplete = true;
		AFn* symC = &sym.fnS;

		void[0][string] nameSet;
		bool prevHadDef = false;
		foreach (size_t i, FParam param; node.params.params){
			if (param.name != "_" && param.name in nameSet){
				st.errs ~= errIdentReuse(param.pos, param.name);
				continue;
			}
			nameSet[param.name] = (void[0]).init;
			AutoExpr autoExpr = cast(AutoExpr)param.type;
			immutable bool isAuto = autoExpr !is null;
			ADataType type;
			if (!isAuto){
				SmErrsVal!ADataType typeRes = eval4Type(param.type, st.stabR, st.ctx,
						st.dep, st.fns);
				if (typeRes.isErr){
					st.errs ~= typeRes.err;
					return;
				}
				type = typeRes.val;
			}
			if (prevHadDef && param.val is null)
				st.errs ~= errFParamNoDef(param.pos, param.name);
			if (isAuto && param.val is null)
				st.errs ~= errAutoNoVal(param.pos);
			if (param.val){
				prevHadDef = true;
				SmErrsVal!AVal valRes = eval4Val(param.val, st.stabR, st.ctx, st.dep,
						st.fns);
				if (valRes.isErr){
					st.errs ~= valRes.err;
					continue;
				}
				if (isAuto){
					type = valRes.val.type;
					if (autoExpr.isConst){
						type = type.constOf;
					}
				}
				if (valRes.val.canCastTo(type, st.ctx)){
					symC.paramsV ~= valRes.val.to(type, st.ctx).val.data.OptVal!(void[]);
				} else {
					st.errs ~= errIncompatType(param.val.pos, type.toString,
							valRes.val.type.toString);
				}
			} else {
				symC.paramsV ~= OptVal!(void[])();
			}
			symC.paramsN ~= param.name;
			symC.paramsT ~= type;
		}
		if (symC.paramsN.length != symC.paramsT.length ||
				symC.paramsN.length != symC.paramsV.length){
			return;
		}
		RFn r = new RFn;
		r.pos = node.pos;
		r.ident = symC.ident.toString;
		r.paramsT = symC.paramsT;
		r.paramsN = symC.paramsN;
		string encodedName = symC.ident[$ - 1].toString.fnNameEncode(symC.paramsT);
		symC.uid = fnNameEncode(symC.ident.toString, symC.paramsT);
		st.fns[symC.uid] = r;

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
	}

	void enumConstIter(EnumConstDef node, ref St1 st){
		if (node.isRecDep(st))
			return;
		ASymbol* sym = st.sMap[node];
		assert (sym);
		if (sym.isComplete) return;
		st.dep[sym] = (void[0]).init;
		scope(exit) st.dep.remove(sym);
		scope(exit) sym.isComplete = true;
		AEnumConst* symC = &sym.enumCS;

		AutoExpr autoExpr = cast(AutoExpr)node.type;
		immutable bool isAuto = autoExpr !is null;
		if (!isAuto){
			SmErrsVal!ADataType typeRes = eval4Type(node.type, st.stabR, st.ctx,
					st.dep, st.fns);
			if (typeRes.isErr){
				st.errs ~= typeRes.err;
				return;
			}
			symC.type = typeRes.val;
		}

		SmErrsVal!AVal valRes = eval4Val(node.val, st.stabR, st.ctx, st.dep,
				st.fns);
		if (valRes.isErr){
			st.errs ~= valRes.err;
			return;
		}
		symC.data = valRes.val.data;
		if (isAuto){
			symC.type = valRes.val.type;
			if (autoExpr.isConst){
				symC.type = symC.type.constOf;
			}
		} else
		if (valRes.val.canCastTo(symC.type, st.ctx)){
			symC.data = valRes.val.to(symC.type, st.ctx).val.data;
		} else {
			st.errs ~= errIncompatType(node.pos, symC.type.toString,
					valRes.val.type.toString);
			return;
		}
	}

	void enumSmIter(EnumSmDef node, ref St1 st){
		if (node.isRecDep(st))
			return;
		ASymbol* sym = st.sMap[node];
		assert (sym);
		if (sym.isComplete) return;
		st.dep[sym] = (void[0]).init;
		scope(exit) st.dep.remove(sym);
		scope(exit) sym.isComplete = true;
		AEnum* symC = &sym.enumS;

		AutoExpr autoExpr = cast(AutoExpr)node.type;
		immutable bool isAuto = autoExpr !is null;
		if (!isAuto){
			SmErrsVal!ADataType typeRes = eval4Type(node.type, st.stabR, st.ctx,
					st.dep, st.fns);
			if (typeRes.isErr){
				st.errs ~= typeRes.err;
				return;
			}
			symC.type = typeRes.val;
		}

		ADataType[] types;
		void[0][string] nameSet;
		foreach (EnumMember member; node.members){
			if (member.name in nameSet)
				st.errs ~= errIdentReuse(member.pos, member.name);
			nameSet[member.name] = (void[0]).init;
			if (member.value is null){
				st.errs ~= errEnumMemValMis(member);
				return;
			}
			SmErrsVal!AVal valRes = eval4Val(member.value, st.stabR, st.ctx,
					st.dep, st.fns);
			if (valRes.isErr){
				st.errs ~= valRes.err;
				return;
			}
			types ~= valRes.val.type;
			symC.memId ~= member.name;
			symC.memVal ~= valRes.val.data;
		}

		if (isAuto){
			ADataType* cType = types.commonType(st.ctx);
			if (cType is null){
				st.errs ~= errIncompatType(node);
				return;
			}
			symC.type = *cType;
			if (autoExpr.isConst){
				symC.type = symC.type.constOf;
			}
		} else {
			foreach (size_t i, ref ADataType type; types){
				if (!type.canCastTo(symC.type, st.ctx))
					st.errs ~= errIncompatType(node.members[i].pos, symC.type.toString,
							type.toString);
			}
		}

		foreach (size_t i; 0 .. symC.memVal.length){
			OptVal!AVal valRes = AVal(types[i], symC.memVal[i]).to(symC.type, st.ctx);
			if (!valRes.isVal){
				st.errs ~= errIncompatType(node.members[i].pos,
						symC.type.toString, types[i].toString);
				continue;
			}
			symC.memVal[i] = valRes.val.to(symC.type, st.ctx).val.data;
		}
	}

	void structIter(StructDef node, ref St1 st){
		if (node.isRecDep(st))
			return;
		ASymbol* sym = st.sMap[node];
		assert (sym);
		if (sym.isComplete) return;
		st.dep[sym] = (void[0]).init;
		scope(exit) st.dep.remove(sym);
		scope(exit) sym.isComplete = true;
		AStruct* symC = &sym.structS;
		Struct s = node.def;

		/// maps aliased name to alias name
		/// `aliasMap["alias_name"] = "the_real_thing"`
		string[string] aliasMap;
		void[0][string] nameSet;
		Visibility[string] aliasVis;
		foreach (AggMember memAbs; s.members){
			AggMemberAlias memAls = cast(AggMemberAlias)memAbs;
			if (memAls is null) continue;
			nameSet[memAls.name] = (void[0]).init;
			if (memAls.name in aliasMap){
				if (memAls.name == This)
					st.errs ~= errMultiInherit(memAls.pos);
				else
					st.errs ~= errIdentReuse(memAls.pos, memAls.name);
				continue;
			}
			aliasMap[memAls.name] = memAls.val.ident;
			aliasVis[memAls.name] = memAls.visibility;
		}

		// remove indirect aliases
		while (true){
			bool done = true;
			foreach (string name; aliasMap.byKey){
				if (auto ptr = aliasMap[name] in aliasMap){
					aliasMap[name] = *ptr;
					done = false;
				}
			}
			if (done) break;
		}

		string bName = null;
		if (string* ptr = This in aliasMap)
			bName = *ptr;
		AggMemberNamed[] fields = s.members
			.map!(m => cast(AggMemberNamed)m).filter!(m => m !is null).array;
		bool erred = false;
		foreach (AggMemberNamed field; fields){
			if (field.name == "_") continue;
			if (field.name in nameSet){
				st.errs ~= errIdentReuse(field.pos, field.name);
				erred = true;
				continue;
			}
			if (field.name == This){
				st.errs ~= errFieldThis(field.pos);
				erred = true;
				continue;
			}
			nameSet[field.name] = (void[0]).init;
		}
		if (erred)
			return;
		if (bName.length){
			immutable size_t ind = fields.countUntil!(f => f.name == bName);
			AggMemberNamed tmp = fields[ind];
			for (size_t i = ind; i > 0; i --)
				fields[i] = fields[i - 1];
			fields[0] = tmp;
		}

		foreach (AggMemberNamed field; fields){
			AutoExpr autoExpr = cast(AutoExpr)field.type;
			immutable bool isAuto = autoExpr !is null;
			ADataType type;
			if (isAuto){
				if (field.val is null){
					st.errs ~= errAutoNoVal(field.pos);
					continue;
				}
			} else {
				SmErrsVal!ADataType typeRes = eval4Type(field.type, st.stabR, st.ctx,
						st.dep, st.fns);
				if (typeRes.isErr){
					st.errs ~= typeRes.err;
					continue;
				}
				type = typeRes.val;
			}
			if (field.val){
				AVal val;
				SmErrsVal!AVal valRes = eval4Val(field.val, st.stabR, st.ctx, st.dep,
						st.fns);
				if (valRes.isErr){
					st.errs ~= valRes.err;
					continue;
				}
				val = valRes.val;
				if (isAuto){
					type = val.type;
					if (autoExpr.isConst){
						type = type.constOf;
					}
				} else
				if (val.canCastTo(type, st.ctx)){
					symC.initD ~= val.to(type, st.ctx).val.data.OptVal!(void[]);
				} else {
					st.errs ~= errIncompatType(field.pos, type.toString,
							val.type.toString);
					continue;
				}
			} else {
				symC.initD ~= type.buildVal;
			}
			foreach (string name; aliasMap.byKey
					.filter!(n => aliasMap[n] == field.name)){
				symC.names[name] = symC.types.length;
				symC.nameVis[name] = aliasVis[name];
			}
			symC.names[field.name] = symC.types.length;
			symC.nameVis[field.name] = field.visibility;
			symC.types ~= type;
		}
	}

	void varIter(VarDef node, ref St1 st){
		if (node.isRecDep(st))
			return;
		ASymbol* sym = st.sMap[node];
		assert (sym);
		if (sym.isComplete) return;
		st.dep[sym] = (void[0]).init;
		scope(exit) st.dep.remove(sym);
		scope(exit) sym.isComplete = true;
		AVar* symC = &sym.varS;
		symC.uid = symC.ident.toString;
		AutoExpr autoExpr = cast(AutoExpr)node.type;
		immutable bool isAuto = autoExpr !is null;
		if (!isAuto){
			SmErrsVal!ADataType typeVal = eval4Type(node.type, st.stabR, st.ctx,
					st.dep, st.fns);
			if (typeVal.isErr){
				st.errs ~= typeVal.err;
				return;
			}
			symC.type = typeVal.val;
		}
		if (node.value){
			SmErrsVal!RExpr res = resolve(node.value, st.stabR, st.ctx,
					st.dep, st.fns);
			if (res.isErr){
				st.errs ~= res.err;
				return;
			}
			SmErrsVal!AVal val = eval4Val(res.val, st.stabR, st.ctx);
			if (val.isErr){
				if (!res.val.hasType){
					st.errs ~= errExprValExpected(node.value.pos);
					return;
				}
				RExpr valExpr = res.val;
				ADataType type = valExpr.type;
				if (isAuto){
					symC.type = type;
				} else
				if (type.canCastTo(symC.type, st.ctx)){
					valExpr = valExpr.to(symC.type, st.ctx).val;
				} else {
					st.errs ~= errIncompatType(node.value.pos, symC.type.toString,
							type.toString);
				}
				st.initers[sym] = valExpr;
				return;
			}
			if (isAuto){
				symC.type = val.val.type;
				symC.initD = val.val.data.OptVal!(void[]);
				if (autoExpr.isConst){
					symC.type = symC.type.constOf;
				}
			} else
			if (val.val.canCastTo(symC.type, st.ctx)){
				symC.initD = val.val.to(symC.type, st.ctx).val.data.OptVal!(void[]);
			} else {
				st.errs ~= errIncompatType(node.value.pos, symC.type.toString,
						val.val.type.toString);
			}
			return;
		}
		if (isAuto){
			st.errs ~= errAutoNoVal(node.pos);
			return;
		}
		OptVal!(void[]) initD = symC.type.buildVal;
		if (!initD.isVal){
			st.errs ~= errInitFail(node.type.pos, symC.type.toString);
			return;
		}
		symC.initD = initD.val.OptVal!(void[]);
	}

	void aliasIter(AliasDef node, ref St1 st){
		if (node.isRecDep(st))
			return;
		ASymbol* sym = st.sMap[node];
		assert (sym);
		if (sym.isComplete) return;
		st.dep[sym] = (void[0]).init;
		scope(exit) st.dep.remove(sym);
		scope(exit) sym.isComplete = true;
		AAlias* symC = &sym.aliasS;
		SmErrsVal!RExpr exprVal = resolve(node.val, st.stabR, st.ctx, st.dep,
				st.fns);
		if (exprVal.isErr){
			st.errs ~= exprVal.err;
			return;
		}
		symC.expr = exprVal.val;
	}

	void unionIter(UnionDef node, ref St1 st){
		if (node.isRecDep(st))
			return;
		ASymbol* sym = st.sMap[node];
		assert (sym);
		if (sym.isComplete) return;
		st.dep[sym] = (void[0]).init;
		scope(exit) st.dep.remove(sym);
		scope(exit) sym.isComplete = true;
		if (NamedUnion sub = cast(NamedUnion)node.def)
			unionNamedDo(sub, sym, st);
		else
		if (UnnamedUnion sub = cast(UnnamedUnion)node.def)
			unionUnnamedDo(sub, sym, st);
	}

	void utestIter(UTest node, ref St1 st){
		if (node.isRecDep(st))
			return;
		ASymbol* sym = st.sMap[node];
		assert (sym);
		if (sym.isComplete) return;
		st.dep[sym] = (void[0]).init;
		scope(exit) st.dep.remove(sym);
		scope(exit) sym.isComplete = true;
		st.errs ~= errUnsup(node);
	}
}

/// converts a Struct to a given AStruct, provided sym1 state
private void structDo(Struct s, AStruct* symC, ref St1 st){
	/// maps aliased name to alias name
	/// `aliasMap["alias_name"] = "the_real_thing"`
	string[string] aliasMap;
	void[0][string] nameSet;
	Visibility[string] aliasVis;
	foreach (AggMember memAbs; s.members){
		AggMemberAlias memAls = cast(AggMemberAlias)memAbs;
		if (memAls is null) continue;
		nameSet[memAls.name] = (void[0]).init;
		if (memAls.name in aliasMap){
			if (memAls.name == This)
				st.errs ~= errMultiInherit(memAls.pos);
			else
				st.errs ~= errIdentReuse(memAls.pos, memAls.name);
			continue;
		}
		aliasMap[memAls.name] = memAls.val.ident;
		aliasVis[memAls.name] = memAls.visibility;
	}

	// remove indirect aliases
	while (true){
		bool done = true;
		foreach (string name; aliasMap.byKey){
			if (auto ptr = aliasMap[name] in aliasMap){
				aliasMap[name] = *ptr;
				done = false;
			}
		}
		if (done) break;
	}

	string bName = null;
	if (string* ptr = This in aliasMap)
		bName = *ptr;
	AggMemberNamed[] fields = s.members
		.map!(m => cast(AggMemberNamed)m).filter!(m => m !is null).array;
	bool erred = false;
	foreach (AggMemberNamed field; fields){
		if (field.name == "_") continue;
		if (field.name in nameSet){
			st.errs ~= errIdentReuse(field.pos, field.name);
			erred = true;
			continue;
		}
		if (field.name == This){
			st.errs ~= errFieldThis(field.pos);
			erred = true;
			continue;
		}
		nameSet[field.name] = (void[0]).init;
	}
	if (erred)
		return;
	if (bName.length){
		immutable size_t ind = fields.countUntil!(f => f.name == bName);
		AggMemberNamed tmp = fields[ind];
		for (size_t i = ind; i > 0; i --)
			fields[i] = fields[i - 1];
		fields[0] = tmp;
	}

	foreach (AggMemberNamed field; fields){
		AutoExpr autoExpr = cast(AutoExpr)field.type;
		immutable bool isAuto = autoExpr !is null;
		ADataType type;
		if (isAuto){
			if (field.val is null){
				st.errs ~= errAutoNoVal(field.pos);
				continue;
			}
		} else {
			SmErrsVal!ADataType typeRes = eval4Type(field.type, st.stabR, st.ctx,
					st.dep, st.fns);
			if (typeRes.isErr){
				st.errs ~= typeRes.err;
				continue;
			}
			type = typeRes.val;
		}
		AVal val;
		if (field.val){
			SmErrsVal!AVal valRes = eval4Val(field.val, st.stabR, st.ctx, st.dep,
					st.fns);
			if (valRes.isErr){
				st.errs ~= valRes.err;
				continue;
			}
			val = valRes.val;
			if (isAuto){
				type = val.type;
				if (autoExpr.isConst){
					type = type.constOf;
				}
			} else
			if (val.canCastTo(type, st.ctx)){
				symC.initD ~= val.to(type, st.ctx).val.data.OptVal!(void[]);
			} else {
				st.errs ~= errIncompatType(field.pos, type.toString,
						val.type.toString);
				continue;
			}
		} else {
			symC.initD ~= type.buildVal;
		}
		foreach (string name; aliasMap.byKey
				.filter!(n => aliasMap[n] == field.name)){
			symC.names[name] = symC.types.length;
			symC.nameVis[name] = aliasVis[name];
		}
		symC.names[field.name] = symC.types.length;
		symC.nameVis[field.name] = field.visibility;
		symC.types ~= type;
	}
}

/// ditto
package SmErr[] structDo(Struct s, AStruct* sym, STab stabR, IdentU[] ctx,
		void[0][ASymbol*] dep, RFn[string] fns){
	St1 st;
	st.stabR = stabR;
	st.stab = stabR.findSt(ctx, ctx);
	st.dep = dep;
	st.fns = fns;
	structDo(s, sym, st);
	return st.errs;
}

/// converts a NamedUnion to a given AUnion, provided sym1 state
package void unionNamedDo(NamedUnion node, ASymbol* sym, ref St1 st){
	AUnion* symC = &sym.unionS;
	/// maps aliased name to alias name
	/// `aliasMap["alias_name"] = "the_real_thing"`
	string[string] aliasMap;
	void[0][string] nameSet;
	Visibility[string] aliasVis;
	foreach (AggMember memAbs; node.members){
		AggMemberAlias memAls = cast(AggMemberAlias)memAbs;
		if (memAls is null) continue;
		nameSet[memAls.name] = (void[0]).init;
		if (memAls.name in aliasMap){
			if (memAls.name == This)
				st.errs ~= errMultiInherit(memAls.pos);
			else
				st.errs ~= errIdentReuse(memAls.pos, memAls.name);
			continue;
		}
		aliasMap[memAls.name] = memAls.val.ident;
		aliasVis[memAls.name] = memAls.visibility;
	}

	// remove indirect aliases
	while (true){
		bool done = true;
		foreach (string name; aliasMap.byKey){
			if (auto ptr = aliasMap[name] in aliasMap){
				aliasMap[name] = *ptr;
				done = false;
			}
		}
		if (done) break;
	}

	bool erred = false;
	foreach (AggMemberNamed field; node.members
			.map!(m => cast(AggMemberNamed)m).filter!(m => m !is null)){
		if (field.name == "_") continue;
		if (field.name in nameSet){
			st.errs ~= errIdentReuse(field.pos, field.name);
			erred = true;
			continue;
		}
		if (field.name == This){
			st.errs ~= errFieldThis(field.pos);
			erred = true;
			continue;
		}
		nameSet[field.name] = (void[0]).init;
	}
	if (erred)
		return;

	symC.initI = size_t.max;
	foreach (size_t i, AggMemberNamed field; node.members
			.map!(m => cast(AggMemberNamed)m).filter!(m => m !is null).enumerate){
		AutoExpr autoExpr = cast(AutoExpr)field.type;
		immutable bool isAuto = autoExpr !is null;
		ADataType type;
		if (isAuto){
			if (field.val is null){
				st.errs ~= errAutoNoVal(field.pos);
				continue;
			}
		} else {
			SmErrsVal!ADataType typeRes = eval4Type(field.type, st.stabR, st.ctx,
					st.dep, st.fns);
			if (typeRes.isErr){
				st.errs ~= typeRes.err;
				continue;
			}
			type = typeRes.val;
		}
		AVal val;
		if (field.val !is null){
			if (symC.initI != size_t.max){
				st.errs ~= errUnionMultiDef(field.pos);
			}
			symC.initI = i;
			SmErrsVal!AVal valRes = eval4Val(field.val, st.stabR, st.ctx, st.dep,
					st.fns);
			if (valRes.isErr){
				st.errs ~= valRes.err;
				continue;
			}
			val = valRes.val;
			if (isAuto){
				type = val.type;
				if (autoExpr.isConst){
					type = type.constOf;
				}
			}	else
			if (val.canCastTo(type, st.ctx)){
				symC.initD = val.to(type, st.ctx).val.data.OptVal!(void[]);
			} else {
				st.errs ~= errIncompatType(field.pos, type.toString,
						val.type.toString);
				continue;
			}
		}
		foreach (string name; aliasMap.byKey
				.filter!(n => aliasMap[n] == field.name)){
			symC.names[name] = symC.types.length;
			symC.nameVis[name] = aliasVis[name];
		}
		symC.names[field.name] = symC.types.length;
		symC.nameVis[field.name] = field.visibility;
		symC.types ~= type;
	}
}

/// ditto
package SmErr[] unionNamedDo(NamedUnion u, ASymbol* sym, STab stabR,
		IdentU[] ctx, void[0][ASymbol*] dep, RFn[string] fns){
	St1 st;
	st.stabR = stabR;
	st.stab = stabR.findSt(ctx, ctx);
	st.dep = dep;
	st.fns = fns;
	unionNamedDo(u, sym, st);
	return st.errs;
}

/// converts a UnnamedUnion to a given AUnion, provided sym1 state
package void unionUnnamedDo(UnnamedUnion node, ASymbol* sym, ref St1 st){
	AUnion* symC = &sym.unionS;
	symC.initI = size_t.max;
	foreach (UnnamedUnionMember member; node.members){
		SmErrsVal!ADataType typeRes = eval4Type(member.type, st.stabR, st.ctx,
				st.dep, st.fns);
		if (typeRes.isErr){
			st.errs ~= typeRes.err;
			continue;
		}
		symC.types ~= typeRes.val;
		if (!member.val) continue;
		if (symC.initI != size_t.max)
			st.errs ~= errUnionMultiDef(member.pos);
		SmErrsVal!AVal valRes = eval4Val(member.val, st.stabR, st.ctx, st.dep,
				st.fns);
		if (valRes.isErr){
			st.errs ~= valRes.err;
			continue;
		}
		if (valRes.val.canCastTo(typeRes.val, st.ctx)){
			symC.initD = valRes.val.to(typeRes.val, st.ctx).val.data.OptVal!(void[]);
			symC.initI = cast(ptrdiff_t)symC.types.length - 1;
		} else {
			st.errs ~= errIncompatType(member.pos, typeRes.val.toString,
					valRes.val.type.toString);
		}
	}
	foreach (size_t i; 0 .. symC.types.length){
		foreach (size_t j; i + 1 .. symC.types.length){
			if (symC.types[i] == symC.types[j])
				st.errs ~= errUnUnionTypeUnique(node.pos, symC.types[i], symC.types[j]);
		}
	}
}

/// ditto
package SmErr[] unionUnnamedDo(UnnamedUnion u, ASymbol* sym, STab stabR,
		IdentU[] ctx, void[0][ASymbol*] dep, RFn[string] fns){
	St1 st;
	st.stabR = stabR;
	st.stab = stabR.findSt(ctx, ctx);
	st.dep = dep;
	st.fns = fns;
	unionUnnamedDo(u, sym, st);
	return st.errs;
}

/// Result Type
package struct S1R{
	/// symbol table
	STab stab;
	/// RFn for each AFn.uid
	RFn[string] fns;
	/// RExpr for each `AUTest.uid`
	RExpr[string] tests;
	/// RExpr to initialize a `ASymbol`
	RExpr[ASymbol*] initers;
}

/// Builds Level 1 Symbol Table
/// Returns: Level 1 Symbol Table, or SmErr[]
package SmErrsVal!S1R stab1Of(ASTNode node, STab stabR, ASymbol*[ASTNode] sMap,
		void[0][ASymbol*] dep, IdentU[] ctx = null){
	St1 st;
	st.stabR = stabR;
	st.stab = stabR.findSt(ctx, ctx);
	st.ctx = ctx.dup;
	st.sMap = sMap;
	st.dep = dep;
	st.fns = new RFn[string];
	It.exec(node, st);
	if (st.errs)
		return SmErrsVal!S1R(st.errs);
	S1R ret = S1R(st.stab, st.fns, st.testExprs, st.initers);
	return SmErrsVal!S1R(ret);
}

/// Fully converts an ASTNode into a ASymbol
/// Returns: Level 1 Symbol Table, or SmErr[]
package SmErrsVal!S1R symDo(ASymbol* sym, STab stabR,
		void[0][ASymbol*] dep, RFn[string] fns){
	assert (sym);
	assert (sym.ast);
	St1 st;
	st.stabR = stabR;
	st.ctx = sym.ident[0 .. $ - 1];
	st.stab = stabR.findSt(st.ctx, st.ctx);
	st.sMap = typeof(st.sMap).init;
	if (sym.ast)
		st.sMap[sym.ast] = sym;
	st.dep = dep;
	st.fns = fns;
	It.exec(sym.ast, st);
	if (st.errs)
		return SmErrsVal!S1R(st.errs);
	return SmErrsVal!S1R(S1R(st.stab, st.fns, st.testExprs, st.initers));
}

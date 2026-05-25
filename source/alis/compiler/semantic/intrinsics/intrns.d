/++
Intrinsics implementations
+/
module alis.compiler.semantic.intrinsics.intrns;

import alis.common,
			 alis.compiler.common,
			 alis.compiler.semantic.common,
			 alis.compiler.semantic.intrinsics.common,
			 alis.compiler.semantic.error,
			 alis.compiler.semantic.eval,
			 alis.compiler.semantic.types,
			 alis.compiler.ast,
			 alis.compiler.ast.rst;

import std.format,
			 std.array,
			 std.algorithm;

debug import std.stdio;

package:
alias CallabilityCheckers = CallabilityCheckersOf!(mixin(__MODULE__));
alias ExprTranslators = ExprTranslatorsOf!(mixin(__MODULE__));

@Intr(IntrN.Type){
	@CallabilityChecker
	bool typeCanCall(AValCT[] params, IdentU[] ctx) pure {
		return false;
	}
	@ExprTranslator
	SmErrsVal!RExpr typeTranslate(IntrSt st){
		return SmErrsVal!RExpr([errIntrUnk(st.pos, IntrN.Type)]);
	}
}

@Intr(IntrN.NoInit){
	@CallabilityChecker
	bool noinitCanCall(AValCT[] params, IdentU[] ctx) pure {
		return params.length == 0;
	}
	@ExprTranslator
	SmErrsVal!RExpr noinitTranslate(IntrSt st){
		RAValCTExpr r = new RAValCTExpr(ADataType.ofNoInit.AValCT);
		r.pos = st.pos;
		return SmErrsVal!RExpr(r);
	}
}

@Intr(IntrN.NoInitVal){
	@CallabilityChecker
	bool noinitvalCanCall(AValCT[] params, IdentU[] ctx){
		return params.length == 0;
	}
	@ExprTranslator
	SmErrsVal!RExpr noinitvalTranslate(IntrSt st){
		RAValCTExpr r = new RAValCTExpr(
				AVal(ADataType.ofNoInit, cast(void[])null).AValCT);
		r.pos = st.pos;
		return SmErrsVal!RExpr(r);
	}
}

@Intr(IntrN.Init){
	@CallabilityChecker
	bool initCanCall(AValCT[] params, IdentU[] ctx){
		if (params.length != 1)
			return false;
		AValCT p = params[0];
		final switch (p.type){
			case AValCT.Type.Symbol:
				return p.symS.isDType;
			case AValCT.Type.Type:
				return true;
			case AValCT.Type.Literal:
			case AValCT.Type.Expr:
			case AValCT.Type.Seq:
				return false;
		}
	}
	@ExprTranslator
	SmErrsVal!RExpr initTranslate(IntrSt st){
		AValCT p = st.params[0];
		ADataType type;
		final switch (p.type){
			case AValCT.Type.Symbol:
				type = p.symS.asType.val;
				break;
			case AValCT.Type.Type:
				type = p.typeT;
				break;
			case AValCT.Type.Literal:
			case AValCT.Type.Expr:
			case AValCT.Type.Seq:
				assert(false);
		}
		OptVal!(void[]) valRes = type.buildVal();
		if (!valRes.isVal){
			return [errInitFail(st.pos, type.toString)].SmErrsVal!RExpr;
		}
		return SmErrsVal!RExpr(new RAValCTExpr(AVal(type, valRes.val).AValCT));
	}
}

@CallabilityChecker
@Intr(IntrN.Int)
@Intr(IntrN.UInt)
@Intr(IntrN.Float)
bool bitXCanCall(AValCT[] params, IdentU[] ctx){
	if (params.length != 1)
		return false;
	AValCT p = params[0];
	if (p.type != AValCT.Type.Literal)
		return false;
	OptVal!size_t x = p.val.as!size_t;
	if (!x.isVal || x.val <= 0)
		return false;
	switch (x.val){
		case 8, 16, 32:
			static if (size_t.sizeof * 8 == 64){
				case 64:
					return true;
			}
		return true;
		default:
			return false;
	}
}

@ExprTranslator{
	@Intr(IntrN.Int)
	SmErrsVal!RExpr intTranslate(IntrSt st){
		ubyte x = size_t.sizeof * 8;
		if (st.params.length != 0)
			x = cast(ubyte)st.params[0].val.as!size_t.val;
		RAValCTExpr r = new RAValCTExpr(ADataType.ofInt(x).AValCT);
		r.pos = st.pos;
		return SmErrsVal!RExpr(r);
	}

	@Intr(IntrN.UInt)
	SmErrsVal!RExpr uintTranslate(IntrSt st){
		ubyte x = size_t.sizeof * 8;
		if (st.params.length != 0)
			x = cast(ubyte)st.params[0].val.as!size_t.val;
		RAValCTExpr r = new RAValCTExpr(ADataType.ofUInt(x).AValCT);
		r.pos = st.pos;
		return SmErrsVal!RExpr(r);
	}

	@Intr(IntrN.Float)
	SmErrsVal!RExpr floatTranslate(IntrSt st){
		ubyte x = size_t.sizeof * 8;
		if (st.params.length != 0)
			x = cast(ubyte)st.params[0].val.as!size_t.val;
		RAValCTExpr r = new RAValCTExpr(ADataType.ofFloat(x).AValCT);
		r.pos = st.pos;
		return SmErrsVal!RExpr(r);
	}

	@Intr(IntrN.Char)
	SmErrsVal!RExpr charTranslate(IntrSt st){
		RAValCTExpr r = new RAValCTExpr(ADataType.ofChar.AValCT);
		r.pos = st.pos;
		return SmErrsVal!RExpr(r);
	}
}

@CallabilityChecker
@Intr(IntrN.Slice)
@Intr(IntrN.Array)
bool firstAndOnlyParamShallBeADataType(AValCT[] params, IdentU[] ctx){
	if (params.length != 1)
		return false;
	if (params[0].type == AValCT.Type.Type)
		return true;
	if (params[0].type == AValCT.Type.Symbol &&
			params[0].symS.isDType)
		return true;
	return false;
}

@Intr(IntrN.Slice) @ExprTranslator
SmErrsVal!RExpr sliceTranslate(IntrSt st){
	RAValCTExpr r = new RAValCTExpr(
			ADataType.ofSlice(st.params[0].asType.val).AValCT);
	r.pos = st.pos;
	return SmErrsVal!RExpr(r);
}

@Intr(IntrN.Array) @ExprTranslator
SmErrsVal!RExpr arrayTranslate(IntrSt st){
	RAValCTExpr r = new RAValCTExpr(
			ADataType.ofArray(st.params[0].asType.val).AValCT);
	r.pos = st.pos;
	return SmErrsVal!RExpr(r);
}

@Intr(IntrN.IsType){
	@CallabilityChecker
	bool isTypeCanCall(AValCT[] params, IdentU[] ctx){
		return params.length == 1;
	}
	@ExprTranslator
	SmErrsVal!RExpr isTypeTranslate(IntrSt st){
		AValCT p = st.params[0];
		RLiteralExpr r;
		final switch (p.type){
			case AValCT.Type.Symbol:
				r = new RLiteralExpr(p.symS.isDType.AVal);
				break;
			case AValCT.Type.Type:
				r = new RLiteralExpr(true.AVal);
				break;
			case AValCT.Type.Literal:
			case AValCT.Type.Expr:
				r = new RLiteralExpr(false.AVal);
				break;
			case AValCT.Type.Seq:
				return SmErrsVal!RExpr([
						errUnsup(st.pos, "AValCT.Type.Seq in $isType")]);
		}
		r.pos = st.pos;
		return SmErrsVal!RExpr(r);
	}
}

@Intr(IntrN.TypeOf){
	@CallabilityChecker
	bool typeOfCanCall(AValCT[] params, IdentU[] ctx){
		return !(typeOfTranslate(IntrSt(string.init, Location.init,
					null, null, null, null, params)).isErr);
	}
	@ExprTranslator
	SmErrsVal!RExpr typeOfTranslate(IntrSt st){
		if (st.params.length != 1){
			return SmErrsVal!RExpr([
					errParamCount(st.pos, IntrN.TypeOf.format!"$%s", 1,
						st.params.length)]);
		}
		ADataType type;
		final switch (st.params[0].type){
			case AValCT.Type.Symbol:
				ASymbol* sym = st.params[0].symS;
				final switch (sym.type){
					case ASymbol.Type.Struct:
					case ASymbol.Type.Union:
					case ASymbol.Type.Enum:
					case ASymbol.Type.Import:
					case ASymbol.Type.UTest:
					case ASymbol.Type.Template:
						return SmErrsVal!RExpr([errCallableIncompat(st.pos,
									IntrN.TypeOf.format!"$%s", st.params.map!(p => p.toString))]);
					case ASymbol.Type.EnumConst:
						type = sym.enumCS.type;
						break;
					case ASymbol.Type.Fn:
						type = ADataType.ofFn(sym.fnS.retT, sym.fnS.paramsT);
						break;
					case ASymbol.Type.Var:
						type = sym.varS.type;
						break;
					case ASymbol.Type.Alias:
						// TODO: decide on $typeOf(alias)
						return SmErrsVal!RExpr([errUnsup(st.pos, "$isType(alias)")]);
				}
				break;
			case AValCT.Type.Type:
				return SmErrsVal!RExpr([errCallableIncompat(st.pos,
							IntrN.TypeOf.format!"$%s", st.params.map!(p => p.toString))]);
				break;
			case AValCT.Type.Literal:
				type = st.params[0].val.type;
				break;
			case AValCT.Type.Expr:
				type = st.params[0].expr.type;
				break;
			case AValCT.Type.Seq:
				return SmErrsVal!RExpr([errUnsup(st.pos, "$isType(sequence)")]);
		}
		RAValCTExpr r = new RAValCTExpr(type.AValCT);
		r.pos = st.pos;
		return SmErrsVal!RExpr(r);
	}
}

@Intr(IntrN.ArrayLen){
	@CallabilityChecker
	bool arrLenCanCall(AValCT[] params, IdentU[] ctx){
		if (params.length == 0 || !params[0].isVal)
			return false;
		ADataType type = params[0].valType.val;
		if (params.length == 1){
			if (type.type == ADataType.Type.Ref)
				type = *type.refT;
			if (type.type != ADataType.Type.Array &&
					type.type != ADataType.Type.Slice)
				return false;
			return true;
		}
		if (params.length == 2){
			if (type.type != ADataType.Type.Ref)
				return false;
			if (type.refT.type != ADataType.Type.Array)
				return false;
			if (!params[1].canCastTo(ADataType.ofUInt))
				return false;
			return true;
		}
		return false;
	}

	@ExprTranslator
	SmErrsVal!RExpr arrLenTranslate(IntrSt st){
		if (st.params.length == 1){
			RArrayLenExpr r = new RArrayLenExpr(st.params[0].toRExpr);
			r.pos = st.pos;
			return SmErrsVal!RExpr(r);
		}
		RArrayLenSetExpr r = new RArrayLenSetExpr(
				st.params[0].toRExpr,
				st.params[1].toRExpr);
		r.pos = st.pos;
		return SmErrsVal!RExpr(r);
	}
}

@Intr(IntrN.ArrayInd){
	@CallabilityChecker
	bool arrIndCanCall(AValCT[] params, IdentU[] ctx){
		if (params.length != 2)
			return false;
		if (!params[0].isVal || !params[1].isVal)
			return false;
		ADataType type = params[0].valType.val;
		if (type.type != ADataType.Type.Array &&
				type.type != ADataType.Type.Slice)
			return false;
		if (!params[1].canCastTo(ADataType.ofUInt))
			return false;
		return true;
	}

	@ExprTranslator
	SmErrsVal!RExpr arrIndTranslate(IntrSt st){
		RArrayIndexExpr r = new RArrayIndexExpr(
				st.params[0].toRExpr,
				st.params[1].toRExpr);
		r.pos = st.pos;
		return SmErrsVal!RExpr(r);
	}
}

@Intr(IntrN.SeqLen){
	@CallabilityChecker
	bool seqLenCanCall(AValCT[] params, IdentU[] ctx){
		return true;
	}
	@ExprTranslator
	SmErrsVal!RExpr seqLenTranslate(IntrSt st){
		return SmErrsVal!RExpr(new RLiteralExpr(st.params.length.AVal));
	}
}

@Intr(IntrN.SeqInd){
	@CallabilityChecker
	bool seqIndCanCall(AValCT[] params, IdentU[] ctx){
		return params.length >= 2 &&
			params[$ - 1].isVal &&
			params[$ - 1].canCastTo(ADataType.ofUInt);
	}

	@ExprTranslator
	SmErrsVal!RExpr seqIndTranslate(IntrSt st){
		OptVal!size_t index = st.params[$ - 1].val.as!size_t;
		if (!index.isVal)
			return SmErrsVal!RExpr([
					errIncompatType(st.pos, ADataType.ofUInt.toString,
						st.params[$ - 1].valType.val.toString)]);
		if (index.val + 1 >= st.params.length)
			return SmErrsVal!RExpr([
					errBounds(st.pos, cast(ptrdiff_t)st.params.length - 1, index.val)]);
		return SmErrsVal!RExpr(st.params[index.val].toRExpr);
	}
}

@Intr(IntrN.UnionIs){
	@CallabilityChecker
	bool unionIsCanCall(AValCT[] params, IdentU[] ctx){
		if (params.length != 1)
			return false;
		RUnionMemberGetExpr p = cast(RUnionMemberGetExpr)(params[0].toRExpr);
		if (p is null)
			return false;
		return true;
	}
	@ExprTranslator
	SmErrsVal!RExpr unionIsTranslate(IntrSt st){
		RUnionMemberGetExpr p = cast(RUnionMemberGetExpr)(st.params[0].toRExpr);
		assert (p !is null);
		RUnionIsExpr r = new RUnionIsExpr(p.val, p.memId);
		r.pos = p.pos;
		return SmErrsVal!RExpr(p);
	}
}

@Intr(IntrN.Members){
	@CallabilityChecker
	bool membersCanCall(AValCT[] params, IdentU[] ctx){
		if (params.length != 1)
			return false;
		AValCT p = params[0];
		final switch (p.type){
			case AValCT.Type.Type:
				final switch (p.typeT.type){
					case ADataType.Type.Seq:
					case ADataType.Type.IntX:
					case ADataType.Type.UIntX:
					case ADataType.Type.FloatX:
					case ADataType.Type.Char:
					case ADataType.Type.Bool:
					case ADataType.Type.Slice:
					case ADataType.Type.Array:
					case ADataType.Type.Ref:
					case ADataType.Type.NoInit:
					case ADataType.Type.Fn:
						return false;
					case ADataType.Type.Struct:
					case ADataType.Type.Union:
					case ADataType.Type.Enum:
						return true;
				}
			case AValCT.Type.Expr:
			case AValCT.Type.Seq:
				return false;
			case AValCT.Type.Symbol:
				final switch (p.symS.type){
					case ASymbol.Type.Struct:
					case ASymbol.Type.Union:
					case ASymbol.Type.Enum:
					case ASymbol.Type.Import:
						return true;
					case ASymbol.Type.Fn:
					case ASymbol.Type.Var:
					case ASymbol.Type.EnumConst:
					case ASymbol.Type.UTest:
					case ASymbol.Type.Alias:
					case ASymbol.Type.Template:
						return false;
				}
			case AValCT.Type.Literal:
				return false;
		}
	}

	@ExprTranslator
	SmErrsVal!RExpr membersTranslate(IntrSt st){
		AValCT p = st.params[0];
		AValCT[] names;
		final switch (p.type){
			case AValCT.Type.Type:
				final switch (p.typeT.type){
					case ADataType.Type.Seq:
					case ADataType.Type.IntX:
					case ADataType.Type.UIntX:
					case ADataType.Type.FloatX:
					case ADataType.Type.Char:
					case ADataType.Type.Bool:
					case ADataType.Type.Slice:
					case ADataType.Type.Array:
					case ADataType.Type.Ref:
					case ADataType.Type.NoInit:
					case ADataType.Type.Fn:
						assert (false);
					case ADataType.Type.Struct:
						AStruct* symC = p.typeT.structS;
						if (symC is null)
							break;
						names = symC.names.byKey
							.filter!(s => symC.exists(s, st.ctx))
							.map!(s => s.AVal.AValCT)
							.array;
						break;
					case ADataType.Type.Union:
						AUnion* symC = p.typeT.unionS;
						names = symC.names.byKey
							.filter!(s => symC.exists(s, st.ctx))
							.map!(s => s.AVal.AValCT)
							.array;
						break;
					case ADataType.Type.Enum:
						AEnum* symC = p.typeT.enumS;
						names = symC.memId
							.map!(s => s.AVal.AValCT)
							.array;
						break;
				}
				break;
			case AValCT.Type.Expr:
			case AValCT.Type.Seq:
				assert (false); // CallabilityChecker should've stopped this
			case AValCT.Type.Symbol:
				final switch (p.symS.type){
					case ASymbol.Type.Struct:
						AStruct* symC = &p.symS.structS;
						names = symC.names.byKey
							.filter!(s => symC.exists(s, st.ctx))
							.map!(s => s.AVal.AValCT)
							.array;
						break;
					case ASymbol.Type.Union:
						AUnion* symC = &p.symS.unionS;
						names = symC.names.byKey
							.filter!(s => symC.exists(s, st.ctx))
							.map!(s => s.AVal.AValCT)
							.array;
						break;
					case ASymbol.Type.Enum:
						AEnum* symC = &p.symS.enumS;
						names = symC.memId
							.map!(s => s.AVal.AValCT)
							.array;
						break;
					case ASymbol.Type.Import:
						return SmErrsVal!RExpr([errUnsup(st.pos, "$members(import)")]);
					case ASymbol.Type.Fn:
					case ASymbol.Type.Var:
					case ASymbol.Type.EnumConst:
					case ASymbol.Type.UTest:
					case ASymbol.Type.Alias:
					case ASymbol.Type.Template:
						assert (false); // CallabilityChecker should've stopped this
				}
				break;
			case AValCT.Type.Literal:
				assert (false); // CallabilityChecker should've stopped this
		}
		RAValCTExpr r = new RAValCTExpr(names.AValCT);
		r.pos = st.pos;
		return SmErrsVal!RExpr(r);
	}
}

@Intr(IntrN.MemberField){
	@CallabilityChecker
	bool memberFieldCanCall(AValCT[] params, IdentU[] ctx){
		if (params.length != 2)
			return false;
		if (!params[0 .. 1].membersCanCall(ctx))
			return false;
		if (params[1].type != AValCT.Type.Literal ||
				params[1].val.type != ADataType.ofString)
			return false;
		return true;
	}

	@ExprTranslator
	SmErrsVal!RExpr memberFieldTranslate(IntrSt st){
		AValCT p = st.params[0];
		assert (st.params[1].type == AValCT.Type.Literal);
		assert (st.params[1].val.type == ADataType.ofString);
		string name = st.params[1].val.as!string.val;
		string res;
		final switch (p.type){
			case AValCT.Type.Type:
				final switch (p.typeT.type){
					case ADataType.Type.Seq:
					case ADataType.Type.IntX:
					case ADataType.Type.UIntX:
					case ADataType.Type.FloatX:
					case ADataType.Type.Char:
					case ADataType.Type.Bool:
					case ADataType.Type.Slice:
					case ADataType.Type.Array:
					case ADataType.Type.Ref:
					case ADataType.Type.NoInit:
					case ADataType.Type.Fn:
						assert (false);
					case ADataType.Type.Struct:
						AStruct* symC = p.typeT.structS;
						if (symC is null || !symC.exists(name, st.ctx))
							return SmErrsVal!RExpr([
									errMemberNoExist(st.pos, p.toString, name)]);
						immutable size_t target = symC.names[name];
						foreach (string n, size_t id; symC.names){
							if (id == target){
								res = n;
								break;
							}
						}
						break;
					case ADataType.Type.Union:
						AUnion* symC = p.typeT.unionS;
						if (!symC.exists(name, st.ctx))
							return SmErrsVal!RExpr([
									errMemberNoExist(st.pos, p.toString, name)]);
						immutable size_t target = symC.names[name];
						foreach (string n, size_t id; symC.names){
							if (id == target){
								res = n;
								break;
							}
						}
						break;
					case ADataType.Type.Enum:
						res = name;
						break;
				}
				break;
			case AValCT.Type.Expr:
			case AValCT.Type.Seq:
				assert (false); // CallabilityChecker should've stopped this
			case AValCT.Type.Symbol:
				final switch (p.symS.type){
					case ASymbol.Type.Struct:
						AStruct* symC = &p.symS.structS;
						if (!symC.exists(name, st.ctx))
							return SmErrsVal!RExpr([
									errMemberNoExist(st.pos, p.toString, name)]);
						immutable size_t target = symC.names[name];
						foreach (string n, size_t id; symC.names){
							if (id == target){
								res = n;
								break;
							}
						}
						break;
					case ASymbol.Type.Union:
						AUnion* symC = &p.symS.unionS;
						if (!symC.exists(name, st.ctx))
							return SmErrsVal!RExpr([
									errMemberNoExist(st.pos, p.toString, name)]);
						immutable size_t target = symC.names[name];
						foreach (string n, size_t id; symC.names){
							if (id == target){
								res = n;
								break;
							}
						}
						break;
					case ASymbol.Type.Enum:
						res = name;
						break;
					case ASymbol.Type.Import:
						return SmErrsVal!RExpr([errUnsup(st.pos, "$members(import)")]);
					case ASymbol.Type.Fn:
					case ASymbol.Type.Var:
					case ASymbol.Type.EnumConst:
					case ASymbol.Type.UTest:
					case ASymbol.Type.Alias:
					case ASymbol.Type.Template:
						assert (false); // CallabilityChecker should've stopped this
				}
				break;
			case AValCT.Type.Literal:
				assert (false); // CallabilityChecker should've stopped this
		}
		RAValCTExpr r = new RAValCTExpr(res.AVal.AValCT);
		r.pos = st.pos;
		return SmErrsVal!RExpr(r);
	}
}

@Intr(IntrN.Member){
	@CallabilityChecker
	bool memberCanCall(AValCT[] params, IdentU[] ctx){
		if (params.length != 2)
			return false;
		if (params[1].type != AValCT.Type.Literal ||
				params[1].val.type != ADataType.ofString)
			return false;
		if (params[0].type == AValCT.Type.Symbol)
			return params[0].symS.type == ASymbol.type.Enum;
		ADataType type = params[0].valType.val;
		if (type.type == ADataType.Type.Ref){
			if (type.refT is null)
				return false;
			type = *(type.refT);
		}
		return type.type == ADataType.Type.Struct ||
			type.type == ADataType.Type.Union;
	}

	@ExprTranslator
	SmErrsVal!RExpr memberTranslate(IntrSt st){
		assert (st.params.length == 2);
		assert (st.params[1].type == AValCT.Type.Literal);
		assert (st.params[1].val.type == ADataType.ofString);
		string name = st.params[1].val.as!string.val;
		if (st.params[0].type == AValCT.Type.Symbol){
			assert (st.params[0].symS.type == ASymbol.Type.Enum);
			AEnum* enumS = &st.params[0].symS.enumS;
			immutable ptrdiff_t index = enumS.memId.countUntil(name);
			if (index < 0){
				return SmErrsVal!RExpr([
						errMemberNoExist(st.pos, enumS.ident.toString, name)]);
			}
			REnumMemberGetExpr r = new REnumMemberGetExpr(
					AVal(enumS.type, enumS.memVal[index]), enumS, name);
			r.pos = st.pos;
			return SmErrsVal!RExpr(r);
		}

		RExpr lhsExpr = st.params[0].toRExpr;
		ADataType type = lhsExpr.type;
		RExpr r;
		assert (type.type == ADataType.Type.Struct ||
				type.type == ADataType.Type.Union ||
				(type.type == ADataType.Type.Ref && type.refT !is null &&
				 (type.refT.type == ADataType.Type.Struct ||
					type.refT.type == ADataType.Type.Union)));
		if (type.type == ADataType.Type.Ref){
			type = *(type.refT);
			if (type.type == ADataType.Type.Struct){
				AStruct* structS = type.structS;
				if (type.type == ADataType.Type.Struct)
					r = new RStructRefMemberGetExpr(lhsExpr,
							structS.names[name],
							type.isConst || (
								structS.ident.length && st.ctx.length &&
								st.ctx[0] != structS.ident[0] &&
								structS.nameVis[name] == Visibility.IPub)
							);
			} else
			if (type.type == ADataType.Type.Union){
				AUnion* unionS = type.unionS;
				r = new RUnionRefMemberGetExpr(lhsExpr,
						unionS.names[name],
						type.isConst || (
							unionS.ident.length && st.ctx.length &&
							st.ctx[0] != unionS.ident[0] &&
							unionS.nameVis[name] == Visibility.IPub)
						);
			}
		} else
		if (type.type == ADataType.Type.Struct){
			AStruct* structS = type.structS;
			if (structS !is null && structS.exists(name, st.ctx))
				r = new RStructMemberGetExpr(lhsExpr,
						structS.names[name],
						type.isConst || (
							structS.ident.length && st.ctx.length &&
							st.ctx[0] != structS.ident[0] &&
							structS.nameVis[name] == Visibility.IPub)
						);
		} else
		if (type.type == ADataType.Type.Union){
			AUnion* unionS = type.unionS;
			if (unionS.exists(name, st.ctx))
				r = new RUnionMemberGetExpr(lhsExpr,
						unionS.names[name],
						type.isConst || (
							unionS.ident.length && st.ctx.length &&
							st.ctx[0] != unionS.ident[0] &&
							unionS.nameVis[name] == Visibility.IPub)
						);
		}
		if (r is null){
			return SmErrsVal!RExpr([
					errMemberNoExist(st.pos, type.toString, name)]);
		}
		r.pos = st.pos;
		return SmErrsVal!RExpr(r);
	}
}

@Intr(IntrN.AttrsOf){
	@CallabilityChecker
	bool attrsOfCanCall(AValCT[] params, IdentU[] ctx){
		if (params.length != 1)
			return false;
		if (params[0].type != AValCT.Type.Symbol)
			return false;
		return true;
	}
	@ExprTranslator
	SmErrsVal!RExpr attrsOfTranslate(IntrSt st){
		return SmErrsVal!RExpr([
				errUnsup(st.pos, "$attrsOf")]);
	}
}

@Intr(IntrN.ByAttrs){
	@CallabilityChecker bool byAttrsCanCall(AValCT[] params, IdentU[] ctx){
		if (params.length != 2)
			return false;
		if (params[0].type != AValCT.Type.Symbol)
			return false;
		// TODO: test params[1]
		return true;
	}
	@ExprTranslator
	SmErrsVal!RExpr byAttrsTranslate(IntrSt st){
		return SmErrsVal!RExpr([
				errUnsup(st.pos, "$byAttrs")]);
	}
}

@Intr(IntrN.Debug){
	@CallabilityChecker
	bool debugCanCall(AValCT[] params, IdentU[] ctx){
		return params.length == 0;
	}
	@ExprTranslator
	SmErrsVal!RExpr debugTranslate(IntrSt st){
		RLiteralExpr r = new RLiteralExpr(
				st.stabR.canFind("$debug".IdentU, [IdentU.init]).AVal);
		r.pos = st.pos;
		return SmErrsVal!RExpr(r);
	}
}

@Intr(IntrN.StackTrace){
	@CallabilityChecker
	bool stackTraceCanCall(AValCT[] params, IdentU[] ctx){
		return params.length == 0;
	}
	@ExprTranslator
	SmErrsVal!RExpr stackTraceTranslate(IntrSt st){
		RStackTraceExpr r = new RStackTraceExpr();
		r.pos = st.pos;
		return SmErrsVal!RExpr(r);
	}
}

@Intr(IntrN.Err){
	@CallabilityChecker
	bool errCanCall(AValCT[] params, IdentU[] ctx){
		return params.length == 1 &&
			params[0].type == AValCT.Type.Literal &&
			params[0].val.type == ADataType.ofString;
	}
	@ExprTranslator
	SmErrsVal!RExpr errTranslate(IntrSt st){
		return SmErrsVal!RExpr([
				errErr(st.pos, st.params[0].val.as!string.val)]);
	}
}

@Intr(IntrN.CTWrite){
	@CallabilityChecker
	bool ctWriteCanCall(AValCT[] params, IdentU[] ctx) pure {
		return params.length != 0;
	}
	@ExprTranslator
	SmErrsVal!RExpr ctWriteTranslate(IntrSt st){
		import std.stdio : writefln;
		writefln!"CTWRITE: %(%s%)"(st.params);
		return SmErrsVal!RExpr(RNoOpExpr.instance);
	}
}

@Intr(IntrN.RTWrite){
	@CallabilityChecker
	bool rtWriteCanCall(AValCT[] params, IdentU[] ctx) pure {
		return params.length == 1;
	}
	@ExprTranslator
	SmErrsVal!RExpr rtWriteTranslate(IntrSt st){
		RTWriteExpr r = new RTWriteExpr;
		r.val = st.params[0].toRExpr;
		r.pos = st.pos;
		return SmErrsVal!RExpr(r);
	}
}

@Intr(IntrN.Negate){
	@CallabilityChecker
	bool negateCanCall(AValCT[] params, IdentU[] ctx){
		if (params.length != 1 || !params[0].isVal)
			return false;
		ADataType type = params[0].valType.val;
		return type.type == ADataType.Type.FloatX ||
			type.type == ADataType.Type.IntX;
	}
	@ExprTranslator
	SmErrsVal!RExpr negateTranslate(IntrSt st){
		RNegExpr r = new RNegExpr(st.params[0].toRExpr);
		r.pos = st.pos;
		return SmErrsVal!RExpr(r);
	}
}

@Intr(IntrN.BitNot){
	@CallabilityChecker
	bool bitNotCanCall(AValCT[] params, IdentU[] ctx){
		if (params.length != 1 || !params[0].isVal)
			return false;
		ADataType type = params[0].valType.val;
		return type.type == ADataType.Type.FloatX ||
			type.type == ADataType.Type.IntX ||
			type.type == ADataType.Type.UIntX;
	}
	@ExprTranslator
	SmErrsVal!RExpr bitNotTranslate(IntrSt st){
		RBitNotExpr r = new RBitNotExpr(st.params[0].toRExpr);
		r.pos = st.pos;
		return SmErrsVal!RExpr(r);
	}
}

@CallabilityChecker
@Intr(IntrN.BitAnd)
@Intr(IntrN.BitOr)
@Intr(IntrN.BitXor)
bool bitBinCanCall(AValCT[] params, IdentU[] ctx){
	return params.length == 2 &&
		params[0].isVal &&
		params[1].isVal &&
		params[0].valType.val == params[1].valType.val;
}

@ExprTranslator
@Intr(IntrN.BitAnd)
@Intr(IntrN.BitOr)
@Intr(IntrN.BitXor)
SmErrsVal!RExpr bitBinTranslate(IntrSt st){
	RExpr r;
	switch (st.name){
		case IntrN.BitAnd:
			r = new RBitAndExpr(st.params[0].toRExpr, st.params[1].toRExpr);
			break;
		case IntrN.BitOr:
			r = new RBitOrExpr(st.params[0].toRExpr, st.params[1].toRExpr);
			break;
		case IntrN.BitXor:
			r = new RBitXorExpr(st.params[0].toRExpr, st.params[1].toRExpr);
			break;
		default:
			assert (false);
	}
	r.pos = st.pos;
	return SmErrsVal!RExpr(r);
}

@CallabilityChecker
@Intr(IntrN.Add)
@Intr(IntrN.Sub)
@Intr(IntrN.Mul)
@Intr(IntrN.Div)
bool arithBinCanCall(AValCT[] params, IdentU[] ctx){
	if (params.length != 2 || !params[0].isVal || !params[1].isVal)
		return false;
	ADataType type = params[0].valType.val;
	if (type.type != ADataType.Type.FloatX &&
			type.type != ADataType.Type.IntX &&
			type.type != ADataType.Type.UIntX)
		return false;
	return type == params[1].valType.val;
}

@ExprTranslator
@Intr(IntrN.Add)
@Intr(IntrN.Sub)
@Intr(IntrN.Mul)
@Intr(IntrN.Div)
SmErrsVal!RExpr arithBinTranslate(IntrSt st){
	RExpr r;
	switch (st.name){
		case IntrN.Add:
			r = new RAddExpr(st.params[0].toRExpr, st.params[1].toRExpr);
			break;
		case IntrN.Sub:
			r = new RSubExpr(st.params[0].toRExpr, st.params[1].toRExpr);
			break;
		case IntrN.Mul:
			r = new RMulExpr(st.params[0].toRExpr, st.params[1].toRExpr);
			break;
		case IntrN.Div:
			r = new RDivExpr(st.params[0].toRExpr, st.params[1].toRExpr);
			break;
		default:
			assert (false);
	}
	r.pos = st.pos;
	return SmErrsVal!RExpr(r);
}

@Intr(IntrN.Mod){
	@CallabilityChecker
	bool modCanCall(AValCT[] params, IdentU[] ctx){
		if (params.length != 2 || !params[0].isVal || !params[1].isVal)
			return false;
		ADataType type = params[0].valType.val;
		if (type.type != ADataType.Type.IntX &&
				type.type != ADataType.Type.UIntX)
			return false;
		return type == params[1].valType.val;
	}
	@ExprTranslator
	SmErrsVal!RExpr modTranslate(IntrSt st){
		RModExpr r = new RModExpr(st.params[0].toRExpr, st.params[1].toRExpr);
		r.pos = st.pos;
		return SmErrsVal!RExpr(r);
	}
}

@CallabilityChecker
@Intr(IntrN.ShiftL)
@Intr(IntrN.ShiftR)
bool shiftCanCall(AValCT[] params, IdentU[] ctx){
	if (params.length != 2 || !params[0].isVal || !params[1].isVal)
		return false;
	ADataType type = params[0].valType.val;
	if (type.type != ADataType.Type.FloatX &&
			type.type != ADataType.Type.IntX &&
			type.type != ADataType.Type.UIntX)
		return false;
	type = params[1].valType.val;
	return type.type == ADataType.Type.UIntX;
}

@ExprTranslator
@Intr(IntrN.ShiftL)
@Intr(IntrN.ShiftR)
SmErrsVal!RExpr shiftTranslate(IntrSt st){
	RExpr r;
	switch (st.name){
		case IntrN.ShiftL:
			r = new RShiftLExpr(st.params[0].toRExpr, st.params[1].toRExpr);
			break;
		case IntrN.ShiftR:
			r = new RShiftRExpr(st.params[0].toRExpr, st.params[1].toRExpr);
			break;
		default:
			assert (false);
	}
	r.pos = st.pos;
	return SmErrsVal!RExpr(r);
}

@CallabilityChecker
@Intr(IntrN.Is)
@Intr(IntrN.IsNot)
@Intr(IntrN.IsLess)
bool cmpCanCall(AValCT[] params, IdentU[] ctx){
	if (params.length != 2 ||
			!params[0].isVal ||
			!params[1].isVal)
		return false;
	return params[0].valType.val == params[1].valType.val;
}

@ExprTranslator
@Intr(IntrN.Is)
@Intr(IntrN.IsNot)
@Intr(IntrN.IsLess)
SmErrsVal!RExpr cmpTranslate(IntrSt st){
	RExpr r;
	switch (st.name){
		case IntrN.Is:
			r = new RCmpIsExpr(st.params[0].toRExpr, st.params[1].toRExpr);
			break;
		case IntrN.IsNot:
			r = new RCmpNotIsExpr(st.params[0].toRExpr, st.params[1].toRExpr);
			break;
		case IntrN.IsLess:
			r = new RCmpLessExpr(st.params[0].toRExpr, st.params[1].toRExpr);
			break;
		default:
			assert (false);
	}
	return SmErrsVal!RExpr(r);
}

@Intr(IntrN.Not){
	@CallabilityChecker
	bool notCanCall(AValCT[] params, IdentU[] ctx){
		return params.length == 1 &&
			params[0].isVal &&
			params[0].valType.val.type == ADataType.Type.Bool;
	}
	@ExprTranslator
	SmErrsVal!RExpr notTranslate(IntrSt st){
		RNotExpr r = new RNotExpr(st.params[0].toRExpr);
		r.pos = st.pos;
		return SmErrsVal!RExpr(r);
	}
}

@Intr(IntrN.To){
	@CallabilityChecker
	bool toCanCall(AValCT[] params, IdentU[] ctx){
		if (params.length != 2 ||
				!params[0].isVal ||
				!(!params[1].isVal && params[1].asType.isVal))
			return false;
		ADataType from = params[0].valType.val;
		ADataType target = params[1].asType.val;
		return from.canCastTo(target, ctx);
	}
	@ExprTranslator
	SmErrsVal!RExpr toTranslate(IntrSt st){
		RExpr param = st.params[0].toRExpr;
		RToExpr r = new RToExpr(param, st.params[1].asType.val);
		r.pos = st.pos;
		return SmErrsVal!RExpr(r);
	}
}

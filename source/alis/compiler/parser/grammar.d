/++
Grammar Rules for Alis
+/
module alis.compiler.parser.grammar;

import alis.common,
			 alis.compiler.ast,
			 alis.compiler.common,
			 alis.compiler.error,
			 alis.compiler.lexer,
			 alis.compiler.parser.parser,
			 alis.compiler.parser.preced;

debug import std.stdio;

import std.algorithm,
			 std.meta,
			 std.conv,
			 std.format,
			 std.array,
			 std.math;

import utils.misc : readBinary, readHexadecimal;

/// alias to TokType
alias TT = TokType;

/// Parser
private alias P = alis.compiler.parser.parser.Parser!(
		Expression, mixin(__MODULE__), ParserOpts(false));

private enum Bin(string Op) = OpBin(Op, PrecedOfBin!Op);
private enum Pre(string Op) = OpPre(Op, PrecedOfPre!Op);
private enum Post(string Op) = OpPost(Op, PrecedOfPost!Op);

/// parses tokens for a Module
/// Returns: Module or error
@GFn
CmpErrVal!Module parseModule(ref TokRange toks){
	Module mod = new Module;

	while (!toks.empty){
		// see if there's a pub:
		Visibility vis = Visibility.Default;
		if (P.expect!(TT.Pub, TT.IPub)(toks)){
			vis = toks.front.type.get!(TT.Pub) ? Visibility.Pub : Visibility.IPub;
			toks.popFront;
		}

		CmpErrVal!AttrList attrs = P.parse!AttrList(toks);
		if (attrs.isErr){
			return CmpErrVal!Module(attrs.err);
		}

		Tok tok = toks.front;
		CmpErrVal!ASTNode ret = P.parse!(DefNode, CCNode)(toks);
		if (ret.isErr)
			return CmpErrVal!Module(ret.err);
		// store
		ASTNode sub = ret.val;
		if (auto subC = cast(Import)sub){
			if (vis == Visibility.IPub)
				return CmpErrVal!Module(errVisibility(tok, "import cannot be ipub"));
		}
		if (auto subC = cast(DefNode)sub){
			P.expectPop!(TT.Semicolon)(toks); // optional semicolon TODO
			GlobDef def = new GlobDef;
			if (auto vars = cast(VarDefList)subC){
				foreach (VarDef v; vars.defs){
					v.attrs = attrs.val;
					v.pos = vars.pos;
				}
			}
			def.def = subC;
			subC.attrs = attrs.val;
			def.visibility = vis;
			mod.defs ~= def;
			// HACK: hacky code below, sadly:
			if (vis == Visibility.IPub){
				if (VarDefList vdl = cast(VarDefList)subC){
					foreach (VarDef var; vdl.defs)
						var.isRO = true;
				}
			}
		} else
		if (auto subC = cast(CCNode)sub){
			mod.cComp ~= subC;
			if (vis != Visibility.Default)
				return CmpErrVal!Module(errVisibility(tok,
							"conditional compilation cannot be `pub` or `ipub`"));
			if (attrs.val !is null && attrs.val.attrs.length)
				return CmpErrVal!Module(errUnxpAttrs(tok));
		} else {
			assert(false, "This should never happpen!");
		}
	}
	return CmpErrVal!Module(mod);
}

/// parses tokens for an Attribute List
/// Returns: AttrList or error. null in case of no attributes
@GFn
CmpErrVal!AttrList parseAttrList(ref TokRange toks){
	if (!toks.front.type.get!(TT.OpTag)){
		return CmpErrVal!AttrList(cast(AttrList) null);
	}
	AttrList ret = new AttrList;
	while (P.expectPop!(TT.OpTag)(toks)){
		CmpErrVal!Expression expr = P.parseExpr!(DEF_P, Expression)(toks);
		if (expr.isErr)
			return CmpErrVal!AttrList(expr.err.errAttrListExpr);
		ret.attrs ~= expr.val;
	}
	return CmpErrVal!AttrList(ret);
}

/// Parses tokens for an Aggregate Member List
/// Returns: AggMemberList or error.
@GFn
CmpErrVal!AggMemberList parseAggMemberList(ref TokRange toks) {
	AggMemberList ret = new AggMemberList;

	AttrList listAttributes;
	CmpErrVal!AttrList attrs = P.parse!AttrList(toks);
	if (attrs.isErr)
		return CmpErrVal!AggMemberList(attrs.err);
	listAttributes = attrs.val;
	Tok front = toks.front;

	Visibility listVisibility = Visibility.Default;
	if (P.expect!(TT.Pub, TT.IPub)(toks)){
		listVisibility = toks.front.type.get!(TT.Pub)
			? Visibility.Pub : Visibility.IPub;
		toks.popFront;
	} else {
		listVisibility = Visibility.Default;
	}

	if (P.expectPop!(TT.Alias)(toks)){
		AggMemberAlias aliasMember = new AggMemberAlias;
		aliasMember.pos = Location(front.line, front.col);

		if (!P.expect!(TT.Identifier)(toks))
			return CmpErrVal!AggMemberList(errUnxpTok(toks.front,
						[TT.Identifier.stringof]));
		aliasMember.name = toks.front.token;
		toks.popFront();

		if (!P.expectPop!(TT.OpAssign)(toks))
			return CmpErrVal!AggMemberList(errUnxpTok(toks.front,
						[TT.OpAssign.stringof]));

		IdentExpr identExpr = new IdentExpr;
		identExpr.ident = toks.front.token;
		aliasMember.val = identExpr;
		toks.popFront();
		ret.members ~= aliasMember;
	} else {
		CmpErrVal!Expression typeExpr = P.parseExpr!(DEF_P, Expression)(toks);
		if (typeExpr.isErr)
			return CmpErrVal!AggMemberList(typeExpr.err);

		front = toks.front;
		// optional ';' for unnamed member
		if (P.expectPop!(TT.Semicolon, TT.OpAssign)(toks)){
			UnnamedUnionMember member = new UnnamedUnionMember;
			member.attrs = listAttributes;
			member.type = typeExpr.val;
			ret.uMembers ~= member;
			if (front.type.get!(TT.OpAssign)){
				CmpErrVal!Expression valExpr = P.parseExpr!(DEF_P, Expression)(toks);
				if (valExpr.isErr)
					return CmpErrVal!AggMemberList(valExpr.err);
				member.val = valExpr.val;
				if (!P.expectPop!(TT.Semicolon)(toks))
					return CmpErrVal!AggMemberList(errUnxpTok(toks.front,
								[TT.Semicolon.stringof]));
			}
			return CmpErrVal!AggMemberList(ret);
		}

		// optional keyVal pairs
		bool firstKeyVal = true;
		do{
			CmpErrVal!KeyVal keyVal = P.parse!KeyVal(toks);
			if (keyVal.isErr){
				if (firstKeyVal)
					break;
				return CmpErrVal!AggMemberList(keyVal.err);
			}
			AggMemberNamed member = new AggMemberNamed;
			member.pos = keyVal.val.pos;
			member.type = typeExpr.val;
			member.name = keyVal.val.key;
			member.val = keyVal.val.val;
			ret.members ~= member;
		} while (P.expectPop!(TT.OpComma)(toks));
	}

	foreach (AggMember member; ret.members){
		member.visibility = listVisibility;
		member.attrs = listAttributes;
	}
	if (!P.expectPop!(TT.Semicolon)(toks))
		return CmpErrVal!AggMemberList(errUnxpTok(toks.front,
					[TT.Semicolon.stringof]));
	return CmpErrVal!AggMemberList(ret);
}

/// parses tokens for a Import
/// Returns: Import or error
@Hook(TT.Import) // trigger on the `import` keyword
@Hook(TokType.Import) CmpErrVal!Import parseImport(ref TokRange toks){
	Import imp = new Import;
	// assume first token is `import`
	assert(P.expect!(TT.Import)(toks));
	toks.popFront; // eat dat import

	// start reading module identifier
	while (!toks.empty && toks.front.type.get!(TT.Identifier)){
		imp.moduleIdent ~= toks.front.token;
		toks.popFront;
		if (!P.expectPop!(TT.OpDot)(toks))
			break;
	}
	if (imp.moduleIdent.length == 0)
		return CmpErrVal!Import(errUnxpTok(toks.front, [TT.Identifier.stringof]));

	imp.name = "_";
	if (P.expectPop!(TT.As)(toks)){
		// read the as part
		if (toks.empty)
			return CmpErrVal!Import(errEOF);
		imp.name = toks.front.token;
		toks.popFront;
	}

	// expect a semicolon
	if (!P.expectPop!(TT.Semicolon)(toks))
		return CmpErrVal!Import(errUnxpTok(toks.front, [TT.Semicolon.stringof]));

	return CmpErrVal!Import(cast(Import) imp);
}

/// parses tokens for a KeyVal
/// Returns: KeyVal or error
@GFn
CmpErrVal!KeyVal parseKeyVal(ref TokRange toks){
	KeyVal ret = new KeyVal;
	// expect an identifer
	if (!P.expect!(TT.Identifier)(toks))
		return CmpErrVal!KeyVal(errUnxpTok(toks.front, [TT.Identifier.stringof]));
	ret.key = toks.front;
	toks.popFront;
	// expect the optional = followed by value
	if (P.expectPop!(TT.OpAssign)(toks)){
		CmpErrVal!Expression expr = P.parseExpr!(DEF_P, Expression)(toks);
		if (expr.isErr){
			return CmpErrVal!KeyVal(expr.err);
		}
		ret.val = expr.val;
	}

	return CmpErrVal!KeyVal(ret);
}

/// parses tokens for a FParam
/// Returns: FParam or error
@GFn
CmpErrVal!FParam parseFParam(ref TokRange toks){
	FParam ret = new FParam;
	CmpErrVal!AttrList attrs = P.parse!AttrList(toks);
	if (attrs.isErr)
		return CmpErrVal!FParam(attrs.err);
	ret.attrs = attrs.val;

	CmpErrVal!Expression type = P.parseExpr!(DEF_P, Expression)(toks);
	if (type.isErr)
		return CmpErrVal!FParam(type.err);
	ret.type = type.val;

	if (P.expect!(TT.Identifier)(toks)){
		ret.name = toks.front.token;
		toks.popFront;
	} else {
		// what we read as type, might be the name, with type being auto
		if (!cast(IdentExpr)ret.type)
			return CmpErrVal!FParam(errUnxpTok(toks.front, [TT.Identifier.stringof]));
		ret.name = (cast(IdentExpr)ret.type).ident;
		ret.type = new AutoExpr;
	}

	// optional value
	if (P.expectPop!(TT.OpAssign)(toks)){
		CmpErrVal!Expression expr = P.parseExpr!(DEF_P, Expression)(toks);
		if (expr.isErr)
			return CmpErrVal!FParam(expr.err);
		ret.val = expr.val;
	}

	return CmpErrVal!FParam(ret);
}

/// parses tokens for a FParamList
/// Returns: FParamList or error
@GFn
CmpErrVal!FParamList parseFParamList(ref TokRange toks){
	FParamList ret = new FParamList;

	if (P.expectPop!(TT.BracketOpen)(toks)){
		while (!P.expectPop!(TT.BracketClose)(toks)){
			CmpErrVal!FParam param = P.parse!FParam(toks);
			if (param.isErr)
				return CmpErrVal!FParamList(param.err);
			ret.params ~= param.val;
			P.expectPop!(TT.OpComma)(toks);
		}
	} else {
		// parse single FParam, which in this case can only be an identifier
		if (!P.expect!(TT.Identifier)(toks))
			return CmpErrVal!FParamList(errUnxpTok(toks.front,
						[TT.Identifier.stringof]));
		ret.params = [new FParam];
		ret.params[0].name = toks.front.token;
		toks.popFront;
	}

	return CmpErrVal!FParamList(ret);
}

/// parses tokens for a TParam
/// Returns: TParam or error
@GFn
CmpErrVal!TParam parseTParam(ref TokRange toks){
	TParam ret;
	// expect `$type`, `alias`, or Expression
	if (P.expectPop!(TT.Alias)(toks)){
		ret = P.expectPop!(TT.OpDots)(toks) ? new TParamAliasSeq : new TParamAlias;
	} else
	if (P.expectPop!(TT.IntrType)(toks)){
		ret = P.expectPop!(TT.OpDots)(toks) ? new TParamTypeSeq : new TParamType;
	} else {
		ret = new TParamSm;
		CmpErrVal!Expression type = P.parseExpr!(DEF_P, Expression)(toks);
		if (type.isErr)
			return CmpErrVal!TParam(type.err);
		(cast(TParamSm)ret).type = type.val;
	}

	// name
	if (!P.expect!(TT.Identifier)(toks))
		return CmpErrVal!TParam(errUnxpTok(toks.front, [TT.Identifier.stringof]));
	ret.name = toks.front.token;
	toks.popFront;

	// specialization?
	if (P.expectPop!(TT.OpColon)(toks)){
		if (P.expectPop!(TT.BracketOpen)(toks)){
			// multiple
			while (!P.expectPop!(TT.BracketClose)(toks)){
				CmpErrVal!Expression expr = P.parseExpr!(DEF_P, Expression)(toks);
				if (expr.isErr)
					return CmpErrVal!(TParam)(expr.err);
				ret.specialization ~= expr.val;
				// eat da comma
				P.expectPop!(TT.OpComma)(toks);
			}
		} else {
			// single
			CmpErrVal!Expression expr = P.parseExpr!(DEF_P, Expression)(toks);
			if (expr.isErr)
				return CmpErrVal!TParam(expr.err);
			ret.specialization ~= expr.val;
		}
	}

	return CmpErrVal!TParam(ret);
}

/// parses tokens for a TParamList
/// Returns: TParamList or error
@GFn
@Hook(TT.TmBracketOpen)
CmpErrVal!TParamList parseTParamList(ref TokRange toks){
	assert (toks.front.type.get!(TT.TmBracketOpen));
	TParamList ret = new TParamList;
	toks.popFront;
	while (!P.expectPop!(TT.BracketClose)(toks)){
		CmpErrVal!TParam tp = P.parse!TParam(toks);
		if (tp.isErr)
			return CmpErrVal!TParamList(tp.err);
		ret.params ~= tp.val;
		// eat da comma
		P.expectPop!(TT.OpComma)(toks);
	}

	// the if condition!
	if (P.expectPop!(TT.If)(toks)){
		CmpErrVal!Expression condition = P.parseExpr!(DEF_P, Expression)(toks);
		if (condition.isErr)
			return CmpErrVal!TParamList(condition.err);
		ret.condition = condition.val;
	}

	return CmpErrVal!TParamList(ret);
}

/// parses tokens for a FnDef
/// Returns: FnDef or error
@GFn
@Hook(TT.Fn)
CmpErrVal!FnDef parseFnDef(ref TokRange toks){
	assert(toks.front.type.get!(TT.Fn));
	toks.popFront;
	FnDef ret = new FnDef;

	// name
	if (!P.expect!(TT.Identifier)(toks))
		return CmpErrVal!FnDef(errUnxpTok(toks.front, [TT.Identifier.stringof]));
	ret.name = toks.front.token;
	toks.popFront;

	if (P.expect!(TT.TmBracketOpen)(toks)){
		CmpErrVal!TParamList tpres = P.parse!(TParamList)(toks);
		if (tpres.isErr)
			return CmpErrVal!FnDef(tpres.err);
		ret.tParams = tpres.val;
	}

	// params
	CmpErrVal!FParamList params = P.parse!FParamList(toks);
	if (params.isErr)
		return CmpErrVal!FnDef(params.err);
	ret.params = params.val;

	// expect ->
	if (!P.expectPop!(TT.OpArrow)(toks))
		return CmpErrVal!FnDef(errUnxpTok(toks.front, [TT.OpArrow.stringof]));

	CmpErrVal!Expression exprA = P.parseExpr!(DEF_P, Expression)(toks);
	if (exprA.isErr)
		return CmpErrVal!FnDef(exprA.err);
	// if next up is `{`, transform it into BlockExpr
	if (P.expect!(TT.CurlyOpen)(toks)){
		CmpErrVal!Block block = P.parse!Block(toks);
		if (block.isErr)
			return CmpErrVal!FnDef(block.err);
		BlockExpr expr = new BlockExpr;
		expr.type = exprA.val;
		expr.block = block.val;
		expr.pos = expr.type.pos;
		ret.body = expr;
	} else {
		ret.body = exprA.val;
		// expect semicolon
		if (!P.expectPop!(TT.Semicolon)(toks))
			return CmpErrVal!FnDef(errUnxpTok(toks.front, [TT.Semicolon.stringof]));
	}
	return CmpErrVal!FnDef(ret);
}

/// parses tokens for a VarDefList
/// Returns: VarDefList or error
@GFn
@Hook(TT.Var)
@Hook(TT.Const)
CmpErrVal!VarDefList parseVarDefList(ref TokRange toks){
	bool isConst = P.expectPop!(TT.Const)(toks);
	if (!isConst && !P.expectPop!(TT.Var)(toks)){
		return CmpErrVal!VarDefList(errUnxpTok(toks.front,
					[TT.Var.stringof, TT.Const.stringof]));
	}
	bool isStatic = P.expectPop!(TT.Static)(toks);
	CmpErrVal!Expression typeRes = P.parseExpr!(DEF_P, Expression)(toks);
	if (typeRes.isErr)
		return CmpErrVal!VarDefList(typeRes.err);
	Expression type = typeRes.val;
	if (isConst){
		if (AutoExpr autoExpr = cast(AutoExpr)type){
			autoExpr.isConst = true;
		} else {
			OpConstPre pre = new OpConstPre;
			pre.operand = type;
			type = pre;
		}
	}

	VarDefList ret = new VarDefList;
	while (!P.expectPop!(TT.Semicolon)(toks)) {
		CmpErrVal!KeyVal keyValResult = P.parse!KeyVal(toks);
		if (keyValResult.isErr)
			return CmpErrVal!VarDefList(keyValResult.err);
		VarDef var = isStatic ? new VarStaticDef : new VarDef;
		var.type = type;
		var.name = keyValResult.val.key;
		var.value = keyValResult.val.val; // TODO handle attrs
		ret.defs ~= var;
		if (!P.expectPop!(TT.OpComma)(toks))
			break; // TODO: fix this mess
	}

	if (!P.expectPop!(TT.Semicolon)(toks))
		return CmpErrVal!VarDefList(errUnxpTok(toks.front,
					[TT.Semicolon.stringof]));
	return CmpErrVal!VarDefList(ret);
}

/// parses tokens for a MixinInitDef
/// Returns: MixinInitDef or error
@GFn
@Hook(TT.Mixin)
CmpErrVal!MixinInitDef parseMixinInitDef(ref TokRange toks){
	assert(toks.front.type.get!(TT.Mixin));
	CmpErrVal!MixinInit val = P.parse!MixinInit(toks);
	if (val.isErr)
		return CmpErrVal!MixinInitDef(val.err);
	MixinInitDef ret = new MixinInitDef;
	ret.mixinInit = val.val;
	return CmpErrVal!MixinInitDef(ret);
}

/// parses tokens for a MixinInitDef
/// Returns: MixinInitDef or error
@GFn
@Hook(TT.Mixin)
CmpErrVal!MixinInitStmnt parseMixinInitStmnt(ref TokRange toks){
	assert(toks.front.type.get!(TT.Mixin));
	CmpErrVal!MixinInit val = P.parse!MixinInit(toks);
	if (val.isErr)
		return CmpErrVal!MixinInitStmnt(val.err);
	MixinInitStmnt ret = new MixinInitStmnt;
	ret.mixinInit = val.val;
	return CmpErrVal!MixinInitStmnt(ret);
}

/// parses tokens for a MixinInit
/// Returns: MixinInit or error
@GFn
@Hook(TT.Mixin)
CmpErrVal!MixinInit parseMixinInit(ref TokRange toks){
	assert(toks.front.type.get!(TT.Mixin));
	MixinInit ret = new MixinInit;
	toks.popFront;
	Tok front = toks.front;
	// parse expression, it should be an OpCallExpr
	CmpErrVal!Expression expr = P.parseExpr!(DEF_P, Expression)(toks);
	if (expr.isErr)
		return CmpErrVal!MixinInit(expr.err);
	OpCallExpr call = cast(OpCallExpr)(expr.val);
	if (!call)
		return CmpErrVal!MixinInit(errUnxpTok(front, [OpCallExpr.stringof]));
	ret.mixn = call.callee;
	ret.params = call.params;
	if (!P.expectPop!(TT.Semicolon)(toks))
		return CmpErrVal!MixinInit(errUnxpTok(toks.front, [TT.Semicolon.stringof]));
	return CmpErrVal!MixinInit(ret);
}

/// parses tokens for a StructDef
/// Returns: StructDef or error
@GFn
@Hook(TT.Struct)
CmpErrVal!StructDef parseStructDef(ref TokRange toks){
	assert(toks.front.type.get!(TT.Struct));
	StructDef ret = new StructDef;
	toks.popFront;
	if (!P.expect!(TT.Identifier)(toks))
		return CmpErrVal!StructDef(errUnxpTok(toks.front,
					[TT.Identifier.stringof]));
	ret.name = toks.front;
	toks.popFront;

	if (P.expect!(TT.TmBracketOpen)(toks)){
		CmpErrVal!TParamList tpres = P.parse!(TParamList)(toks);
		if (tpres.isErr)
			return CmpErrVal!StructDef(tpres.err);
		ret.tParams = tpres.val;
	}

	CmpErrVal!Struct def = P.parse!Struct(toks);
	if (def.isErr)
		return CmpErrVal!StructDef(def.err);
	ret.def = def.val;
	return CmpErrVal!StructDef(cast(StructDef) ret);
}

/// Parses tokens for a Struct body
/// Returns: Struct or error
@GFn
@Hook(TT.CurlyOpen)
CmpErrVal!Struct parseStruct(ref TokRange toks){
	assert(toks.front.type.get!(TT.CurlyOpen));
	toks.popFront;
	Struct ret = new Struct;
	while (!P.expect!(TT.CurlyClose)(toks)){
		CmpErrVal!ASTNode members = P.parse!(CCNode, MixinInit, AggMemberList)
			(toks);
		if(members.isErr)
			return CmpErrVal!Struct(members.err);
		if (auto subC = cast(CCNode)members.val){
			ret.cComp ~= subC;
		} else
		if (auto subC = cast(MixinInit)members.val){
			ret.mixinInits ~= subC;
		} else
		if (auto subC = cast(AggMemberList)members.val){
			ret.members ~= subC.members;
		} else {
			assert(false, "fix the parser!");
		}
	}
	if (!P.expectPop!(TT.CurlyClose)(toks))
		return CmpErrVal!Struct(errUnxpTok(toks.front,
					[TT.CurlyClose.stringof]));
	return CmpErrVal!Struct(ret);
}

/// parses tokens for a UnionDef
/// Returns: NamedUnionDef, UnNamedUnionDef or error
@GFn
@Hook(TT.Union)
CmpErrVal!UnionDef parseUnionDef(ref TokRange toks){
	if (!P.expectPop!(TT.Union)(toks))
		return CmpErrVal!UnionDef(errUnxpTok(toks.front, [TT.Union.stringof]));
	if (!P.expect!(TT.Identifier)(toks))
		return CmpErrVal!UnionDef(errUnxpTok(toks.front, [TT.Identifier.stringof]));
	UnionDef ret = new UnionDef;
	ret.name = toks.front;
	toks.popFront;
	if (P.expect!(TT.TmBracketOpen)(toks)){
		CmpErrVal!TParamList tpres = P.parse!(TParamList)(toks);
		if (tpres.isErr)
			return CmpErrVal!UnionDef(tpres.err);
		ret.tParams = tpres.val;
	}

	CmpErrVal!Union def = P.parse!Union(toks);
	if (def.isErr)
		return CmpErrVal!UnionDef(def.err);
	ret.def = def.val;
	return CmpErrVal!UnionDef(ret);
}

/// parses a Union (body)
/// Returns: Union or error
@GFn
@Hook(TT.CurlyOpen)
CmpErrVal!Union parseUnion(ref TokRange toks){
	assert (toks.front.type.get!(TT.CurlyOpen));
	Tok front = toks.front;
	toks.popFront;
	Union ret;
	AggMemberList members = new AggMemberList;
	CCNode[] cComp;
	MixinInit[] mixinInits;
	while (!P.expect!(TT.CurlyClose)(toks)){
		CmpErrVal!ASTNode unionMember = P.parse!(CCNode, MixinInit, AggMemberList)
			(toks);
		if(unionMember.isErr)
			return CmpErrVal!Union(unionMember.err);
		if (auto subC = cast(CCNode)unionMember.val){
			cComp ~= subC;
		} else
		if (auto subC = cast(MixinInit)unionMember.val){
			mixinInits ~= subC;
		} else
		if (auto subC = cast(AggMemberList)unionMember.val){
			members.members ~= subC.members;
			members.uMembers ~= subC.uMembers;
		} else {
			assert(false, "fix the parser!");
		}
	}
	if (!P.expectPop!(TT.CurlyClose)(toks))
		return CmpErrVal!Union(errUnxpTok(toks.front, [TT.Union.stringof]));

	if (members.members.length + members.uMembers.length == 0){
		if (cComp.length + mixinInits.length == 0)
			return CmpErrVal!Union(new UnnamedUnion);
		ret = new UnkUnion;
		ret.cComp = cComp;
		ret.mixinInits = mixinInits;
		return CmpErrVal!Union(ret);
	}

	bool allNamed = members.members.length && !members.uMembers.length,
			 allUnnamed = members.uMembers.length && !members.members.length;
	if (allNamed == allUnnamed)
		return CmpErrVal!Union(errrUnionMixed(front));

	if (allNamed){
		ret = new NamedUnion;
		(cast(NamedUnion)ret).members = members.members;
	} else
	if (allUnnamed){
		ret = new UnnamedUnion;
		(cast(UnnamedUnion)ret).members = members.uMembers;
	} else {
		return CmpErrVal!Union(errrUnionMixed(front));
	}
	ret.cComp = cComp;
	ret.mixinInits = mixinInits;
	return CmpErrVal!Union(ret);
}

/// parses tokens for a EnumDef
/// Returns: EnumDef or error
/// nafees doing it
@GFn
@Hook(TT.Enum)
CmpErrVal!EnumDef parseEnumDef(ref TokRange toks){
	assert(toks.front.type.get!(TT.Enum));
	toks.popFront;
	// type
	CmpErrVal!Expression type = P.parseExpr!(DEF_P, Expression)(toks);
	if (type.isErr)
		return CmpErrVal!EnumDef(type.err);

	// name
	if (!P.expect!(TT.Identifier)(toks))
		return CmpErrVal!EnumDef(errUnxpTok(toks.front, [TT.Identifier.stringof]));
	string name = toks.front.token;
	toks.popFront;

	// optional param list
	TParamList tParams = null;
	if (P.expect!(TT.TmBracketOpen)(toks)){
		CmpErrVal!TParamList tpres = P.parse!(TParamList)(toks);
		if (tpres.isErr)
			return CmpErrVal!EnumDef(tpres.err);
		tParams = tpres.val;
	}

	// is it `=` ?
	if (P.expectPop!(TT.OpAssign)(toks)){
		CmpErrVal!Expression val = P.parseExpr!(DEF_P, Expression)(toks);
		if (val.isErr)
			return CmpErrVal!EnumDef(val.err);
		EnumConstDef ret = new EnumConstDef;
		ret.type = type.val;
		ret.name = name;
		ret.tParams = tParams;
		ret.val = val.val;
		if (!P.expectPop!(TT.Semicolon)(toks))
			return CmpErrVal!EnumDef(errUnxpTok(toks.front,
						[TT.Semicolon.stringof]));
		return CmpErrVal!EnumDef(ret);
	}

	EnumSmDef ret = new EnumSmDef;
	ret.type = type.val;
	ret.name = name;
	ret.tParams = tParams;

	if (!P.expectPop!(TT.CurlyOpen)(toks))
		return CmpErrVal!EnumDef(errUnxpTok(toks.front, [TT.CurlyOpen.stringof]));
	while (!P.expectPop!(TT.CurlyClose)(toks)){
		CmpErrVal!ASTNode member = P.parse!(CCNode, MixinInit, EnumMember)(toks);
		if (member.isErr)
			return CmpErrVal!EnumDef(member.err);

		if (cast(CCNode)member.val){
			ret.cComp ~= cast(CCNode)member.val;
		} else
		if (cast(EnumMember)member.val){
			ret.members ~= cast(EnumMember)member.val;
		} else
		if (cast(MixinInit)member.val){
			ret.mixinInits ~= cast(MixinInit)member.val;
		} else {
			assert(false, "fix the parser!");
		}

		// there shall be a comma now!
		P.expectPop!(TT.OpComma)(toks); // TODO: error if no comma?
	}
	/*if (!P.expectPop!(TT.Semicolon)(toks))
		return CmpErrVal!EnumDef(errUnxpTok(toks.front, [TT.Semicolon.stringof]));*/

	return CmpErrVal!EnumDef(ret);
}

/// parses tokens for EnumMember
/// Returns: EnumMember or error
@GFn
CmpErrVal!EnumMember parseEnumMember(ref TokRange toks){
	EnumMember ret = new EnumMember;
	if (toks.front.type.get!(TT.OpTag)){
		CmpErrVal!AttrList attrs = P.parse!AttrList(toks);
		if (attrs.isErr)
			return CmpErrVal!EnumMember(attrs.err);
		ret.attrs = attrs.val;
	}
	if (!P.expect!(TT.Identifier)(toks))
		return CmpErrVal!EnumMember(errUnxpTok(toks.front,
					[TT.Identifier.stringof]));
	ret.name = toks.front;
	toks.popFront;
	if (!P.expectPop!(TT.OpAssign)(toks))
		return CmpErrVal!EnumMember(ret);
	CmpErrVal!Expression val = P.parseExpr!(DEF_P, Expression)(toks);
	if (val.isErr)
		return CmpErrVal!EnumMember(val.err);
	ret.value = val.val;
	return CmpErrVal!EnumMember(ret);
}

/// parses tokens for a AliasDef
/// Returns: AliasDef or error
@GFn
@Hook(TT.Alias)
CmpErrVal!AliasDef parseAliasDef(ref TokRange toks){
	assert(toks.front.type.get!(TT.Alias));
	toks.popFront;
	AliasDef ret = new AliasDef;
	if (!P.expect!(TT.Identifier)(toks))
		return CmpErrVal!AliasDef(errUnxpTok(toks.front, [TT.Identifier.stringof]));
	ret.name = toks.front.token;
	toks.popFront;
	// optional template params
	if (P.expect!(TT.TmBracketOpen)(toks)){
		CmpErrVal!TParamList tparams = P.parse!TParamList(toks);
		if (tparams.isErr)
			return CmpErrVal!AliasDef(tparams.err);
		ret.tParams = tparams.val;
	}
	if (!P.expectPop!(TT.OpAssign)(toks))
		return CmpErrVal!AliasDef(errUnxpTok(toks.front, [TT.OpAssign.stringof]));
	CmpErrVal!Expression expr = P.parseExpr!(DEF_P, Expression)(toks);
	if (expr.isErr)
		return CmpErrVal!AliasDef(expr.err);
	ret.val = expr.val;
	if (!P.expectPop!(TT.Semicolon)(toks))
		return CmpErrVal!AliasDef(errUnxpTok(toks.front, [TT.Semicolon.stringof]));
	return CmpErrVal!AliasDef(ret);
}

/// parses tokens for a TemplateDef
/// Returns: TemplateDef or error
@GFn
@Hook(TT.Template)
CmpErrVal!TemplateDef parseTemplateDef(ref TokRange toks){
	assert(toks.front.type.get!(TT.Template));
	toks.popFront;
	TemplateDef ret = P.expectPop!(TT.Mixin)(toks)
		? new TemplateMixinDef : new TemplateDef;
	if (!P.expect!(TT.Identifier)(toks))
		return CmpErrVal!TemplateDef(errUnxpTok(toks.front,
					[TT.Identifier.stringof]));
	ret.name = toks.front;
	toks.popFront;
	CmpErrVal!TParamList tparams = P.parse!TParamList(toks);
	if (tparams.isErr)
		return CmpErrVal!TemplateDef(tparams.err);
	ret.tParams = tparams.val;
	CmpErrVal!AnyBlock body = P.parse!AnyBlock(toks);
	if (body.isErr)
		return CmpErrVal!TemplateDef(body.err);
	ret.body = body.val;
	return CmpErrVal!TemplateDef(ret);
}

/// parses tokens for a UTest
/// Returns: UTest or error
@GFn
@Hook(TT.UTest)
CmpErrVal!UTest parseUTest(ref TokRange toks){
	assert (toks.front.type.get!(TT.UTest));
	UTest ret = new UTest;
	toks.popFront;
	if (P.expect!(TT.LiteralString)(toks)){
		ret.desc = cast(string)toks.front.token[1 .. $-1].strUnescape;
		toks.popFront;
	}
	CmpErrVal!Block block = P.parse!Block(toks);
	if (block.isErr)
		return CmpErrVal!UTest(block.err);
	ret.body = block.val;
	return CmpErrVal!UTest(ret);
}

/// parses tokens for a AnyBlock
/// Returns: AnyBlock or error
/// nafees doing it
@GFn
@Hook(TT.CurlyOpen)
CmpErrVal!AnyBlock parseAnyBlock(ref TokRange toks){
	assert(toks.front.type.get!(TT.CurlyOpen));
	AnyBlock ret = new AnyBlock;
	toks.popFront;
	size_t count = 1;
	while (true){
		Tok front = toks.front;
		toks.popFront;
		if (front.type.get!(TT.CurlyOpen))
			count ++;
		else
		if (front.type.get!(TT.CurlyClose))
			count --;
		if (!count)
			break;
		ret.body ~= front;
	}
	return CmpErrVal!AnyBlock(ret);
}

/// parses tokens for DefNode as a Statement
/// Returns: DefStatement or error
@GFn
@Hook(TT.Var) @Hook(TT.Const)
@Hook(TT.Template)
/*@Hook(TT.Fn) // these conflict with expressions
@Hook(TT.Struct)
@Hook(TT.Union)*/
@Hook(TT.Enum)
@Hook(TT.Alias)
@Hook(TT.OpTag)
CmpErrVal!DefStatement parseDefStatement(ref TokRange toks){
	DefStatement ret = new DefStatement;
	CmpErrVal!AttrList attrs = CmpErrVal!AttrList(null);
	if (P.expect!(TT.OpTag)(toks)){
		attrs = P.parse!AttrList(toks);
		if (attrs.isErr)
			return CmpErrVal!DefStatement(attrs.err);
	}
	CmpErrVal!DefNode def = P.parse!DefNode(toks);
	if (def.isErr)
		return CmpErrVal!DefStatement(def.err);
	if (auto vars = cast(VarDefList)(def.val)){
		foreach (VarDef v; vars.defs){
			v.attrs = attrs.val;
			v.pos = vars.pos;
		}
	}
	ret.def = def.val;
	ret.def.attrs = attrs.val;
	return CmpErrVal!DefStatement(ret);
}

/// parses tokens for a Block
/// Returns: Block or error
@GFn
@Hook(TT.CurlyOpen)
CmpErrVal!Block parseBlock(ref TokRange toks){
	assert(toks.front.type.get!(TT.CurlyOpen));
	Block ret = new Block;
	toks.popFront;
	while (!P.expectPop!(TT.CurlyClose)(toks)){
		CmpErrVal!Statement stmnt = P.parse!Statement(toks);
		if (stmnt.isErr)
			return CmpErrVal!Block(stmnt.err);
		ret.statements ~= stmnt.val;
	}
	return CmpErrVal!Block(ret);
}

/// parses tokens for a Return
/// Returns: Return or error
@GFn
@Hook(TT.Return)
CmpErrVal!Return parseReturn(ref TokRange toks){
	assert(toks.front.type.get!(TT.Return));
	toks.popFront;
	Return ret = new Return;
	if (P.expectPop!(TT.Semicolon)(toks))
		return CmpErrVal!Return(ret);
	CmpErrVal!Expression val = P.parseExpr!(DEF_P, Expression)(toks);
	if (val.isErr)
		return CmpErrVal!Return(val.err);
	ret.val = val.val;
	if (!P.expectPop!(TT.Semicolon)(toks))
		return CmpErrVal!Return(errUnxpTok(toks.front, [TT.Semicolon.stringof]));
	return CmpErrVal!Return(ret);
}

/// parses tokens for a If
/// Returns: If or error
@GFn
@Hook(TT.If)
CmpErrVal!If parseIf(ref TokRange toks){
	assert (toks.front.type.get!(TT.If));
	toks.popFront;
	If ret = new If;
	CmpErrVal!Expression condition = P.parseExpr!(DEF_P, Expression)(toks);
	if (condition.isErr)
		return CmpErrVal!If(condition.err);
	ret.condition = condition.val;
	// on true statement
	CmpErrVal!Statement body = P.parse!Statement(toks);
	if (body.isErr)
		return CmpErrVal!If(body.err);
	ret.onTrue = body.val;
	if (P.expectPop!(TT.Else)(toks)){
		body = P.parse!Statement(toks);
		if (body.isErr)
			return CmpErrVal!If(body.err);
		ret.onFalse = body.val;
	}
	return CmpErrVal!If(ret);
}

/// parses tokens for a StaticIf
/// Returns: StaticIf or error
@GFn
@Hook(TT.StaticIf)
CmpErrVal!StaticIf parseStaticIf(ref TokRange toks){
	assert (toks.front.type.get!(TT.StaticIf));
	toks.popFront;
	StaticIf ret = new StaticIf;
	CmpErrVal!Expression condition = P.parseExpr!(DEF_P, Expression)(toks);
	if (condition.isErr)
		return CmpErrVal!StaticIf(condition.err);
	ret.conditions ~= condition.val;
	// on true block
	CmpErrVal!AnyBlock body = P.parse!AnyBlock(toks);
	if (body.isErr)
		return CmpErrVal!StaticIf(body.err);
	ret.onTrue ~= body.val;
	while (P.expectPop!(TT.Else)(toks)){
		if (P.expectPop!(TT.StaticIf)(toks)){
			condition = P.parseExpr!(DEF_P, Expression)(toks);
			if (condition.isErr)
				return CmpErrVal!StaticIf(condition.err);
			body = P.parse!AnyBlock(toks);
			if (body.isErr)
				return CmpErrVal!StaticIf(body.err);
			ret.conditions ~= condition.val;
			ret.onTrue ~= body.val;
			continue;
		}
		body = P.parse!AnyBlock(toks);
		if (body.isErr)
			return CmpErrVal!StaticIf(body.err);
		ret.onFalse = body.val;
		break;
	}
	return CmpErrVal!StaticIf(ret);
}

/// parses tokens for a For
/// Returns: For or error
@GFn
@Hook(TT.For)
CmpErrVal!For parseFor(ref TokRange toks){
	assert(toks.front.type.get!(TT.For));
	toks.popFront;
	For ret = new For;
	if (!P.expectPop!(TT.BracketOpen)(toks))
		return CmpErrVal!For(errUnxpTok(toks.front,
					[TT.BracketOpen.stringof]));
	CmpErrVal!Expression expr = P.parseExpr!(DEF_P, Expression)(toks);
	if (expr.isErr)
		return CmpErrVal!For(expr.err);
	// if next is semicolon, then this must be the counter identifier
	if (P.expectPop!(TT.Semicolon)(toks)){
		IdentExpr ident = cast(IdentExpr)expr.val;
		if (ident is null)
			return CmpErrVal!For(errUnxpTok(toks.front,
						[IdentExpr.stringof]));
		ret.countIdent = ident.ident;
		// now do the value type expr
		expr = P.parseExpr!(DEF_P, Expression)(toks);
		if (expr.isErr)
			return CmpErrVal!For(expr.err);
	}
	ret.valType = expr.val;
	// valIdent
	if (!P.expect!(TT.Identifier)(toks))
		return CmpErrVal!For(errUnxpTok(toks.front,
					[TT.Identifier.stringof]));
	ret.valIdent = toks.front.token;
	toks.popFront;
	if (!P.expectPop!(TT.Semicolon)(toks))
		return CmpErrVal!For(errUnxpTok(toks.front,
					[TT.Semicolon.stringof]));
	// range expr
	expr = P.parseExpr!(DEF_P, Expression)(toks);
	if (expr.isErr)
		return CmpErrVal!For(expr.err);
	ret.range = expr.val;
	if (!P.expectPop!(TT.BracketClose)(toks))
		return CmpErrVal!For(errUnxpTok(toks.front,
					[TT.BracketClose.stringof]));
	// body
	CmpErrVal!Statement body = P.parse!Statement(toks);
	if (body.isErr)
		return CmpErrVal!For(body.err);
	ret.body = body.val;
	return CmpErrVal!For(ret);
}

/// parses tokens for a StaticFor
/// Returns: StaticFor or error
@GFn
@Hook(TT.StaticFor)
CmpErrVal!StaticFor parseStaticFor(ref TokRange toks){
	assert(toks.front.type.get!(TT.StaticFor));
	toks.popFront;
	StaticFor ret = new StaticFor;
	if (!P.expectPop!(TT.BracketOpen)(toks))
		return CmpErrVal!StaticFor(errUnxpTok(toks.front,
					[TT.BracketOpen.stringof]));
	CmpErrVal!Expression expr = P.parseExpr!(DEF_P, Expression)(toks);
	if (expr.isErr)
		return CmpErrVal!StaticFor(expr.err);
	// if next is semicolon, then this must be the counter identifier
	if (P.expectPop!(TT.Semicolon)(toks)){
		IdentExpr ident = cast(IdentExpr)expr.val;
		if (ident is null)
			return CmpErrVal!StaticFor(errUnxpTok(toks.front,
						[IdentExpr.stringof]));
		ret.countIdent = ident.ident;
		// now do the value type expr
		expr = P.parseExpr!(DEF_P, Expression)(toks);
		if (expr.isErr)
			return CmpErrVal!StaticFor(expr.err);
	}
	ret.valType = expr.val;
	// valIdent
	if (!P.expect!(TT.Identifier)(toks))
		return CmpErrVal!StaticFor(errUnxpTok(toks.front,
					[TT.Identifier.stringof]));
	ret.valIdent = toks.front.token;
	toks.popFront;
	if (!P.expectPop!(TT.Semicolon)(toks))
		return CmpErrVal!StaticFor(errUnxpTok(toks.front,
					[TT.Semicolon.stringof]));
	// range expr
	expr = P.parseExpr!(DEF_P, Expression)(toks);
	if (expr.isErr)
		return CmpErrVal!StaticFor(expr.err);
	ret.range = expr.val;
	if (!P.expectPop!(TT.BracketClose)(toks))
		return CmpErrVal!StaticFor(errUnxpTok(toks.front,
					[TT.BracketClose.stringof]));
	// body
	CmpErrVal!AnyBlock body = P.parse!AnyBlock(toks);
	if (body.isErr)
		return CmpErrVal!StaticFor(body.err);
	ret.body = body.val;
	return CmpErrVal!StaticFor(ret);
}

/// parses tokens for a While
/// Returns: While or error
@GFn
@Hook(TT.While)
CmpErrVal!While parseWhile(ref TokRange toks){
	assert(toks.front.type.get!(TT.While));
	While ret = new While;
	toks.popFront;
	CmpErrVal!Expression condition = P.parseExpr!(DEF_P, Expression)(toks);
	if (condition.isErr)
		return CmpErrVal!While(condition.err);
	ret.condition = condition.val;
	CmpErrVal!Statement body = P.parse!Statement(toks);
	if (body.isErr)
		return CmpErrVal!While(body.err);
	ret.body = body.val;
	return CmpErrVal!While(ret);
}

/// parses tokens for a DoWhile
/// Returns: DoWhile or error
@GFn
@Hook(TT.Do)
CmpErrVal!DoWhile parseDoWhile(ref TokRange toks){
	assert(toks.front.type.get!(TT.Do));
	DoWhile ret = new DoWhile;
	toks.popFront;
	CmpErrVal!Statement body = P.parse!Statement(toks);
	if (body.isErr)
		return CmpErrVal!DoWhile(body.err);
	ret.body = body.val;
	if (!P.expectPop!(TT.While)(toks))
		return CmpErrVal!DoWhile(errUnxpTok(toks.front,
					[TT.While.stringof]));
	CmpErrVal!Expression condition = P.parseExpr!(DEF_P, Expression)(toks);
	if (condition.isErr)
		return CmpErrVal!DoWhile(condition.err);
	ret.condition = condition.val;
	if (!P.expectPop!(TT.Semicolon)(toks))
		return CmpErrVal!DoWhile(errUnxpTok(toks.front,
					[TT.Semicolon.stringof]));
	return CmpErrVal!DoWhile(ret);
}

/// parses tokens for a Switch
/// Returns: Switch or error
@GFn
@Hook(TT.Switch)
CmpErrVal!Switch parseSwitch(ref TokRange toks){
	assert(toks.front.type.get!(TT.Switch));
	Switch ret = new Switch;
	toks.popFront;
	CmpErrVal!Expression val = P.parseExpr!(DEF_P, Expression)(toks);
	if (val.isErr)
		return CmpErrVal!Switch(val.err);
	ret.val = val.val;
	bool repeat = true;
	while (repeat){
		CmpErrVal!ASTNode sub = P.parse!(Case, MixinInit, CCNode)(toks);
		if (sub.isErr)
			return CmpErrVal!Switch(sub.err);
		if (auto subC = cast(Case)sub.val){
			ret.cases ~= subC;
			if (cast(CaseDef)subC)
				repeat = false; // switch case is terminated by `case _`
		} else
		if (auto subC = cast(MixinInit)sub.val){
			ret.mixinInits ~= subC;
		} else
		if (auto subC = cast(CCNode)sub.val){
			ret.cComp ~= subC;
		} else {
			assert (false, "fix the parser pls!");
		}
	}
	return CmpErrVal!Switch(ret);
}

/// parses tokens for a StaticSwitch
/// Returns: StaticSwitch or error
@GFn
@Hook(TT.StaticSwitch)
CmpErrVal!StaticSwitch parseStaticSwitch(ref TokRange toks){
	assert(toks.front.type.get!(TT.StaticSwitch));
	StaticSwitch ret = new StaticSwitch;
	toks.popFront;
	CmpErrVal!Expression val = P.parseExpr!(DEF_P, Expression)(toks);
	if (val.isErr)
		return CmpErrVal!StaticSwitch(val.err);
	ret.val = val.val;
	bool repeat = true;
	while (repeat){
		CmpErrVal!ASTNode sub = P.parse!(StaticCase, MixinInit, CCNode)(toks);
		if (sub.isErr)
			return CmpErrVal!StaticSwitch(sub.err);
		if (auto subC = cast(StaticCase)sub.val){
			ret.cases ~= subC;
			if (cast(StaticCaseDef)subC)
				repeat = false; // switch case is terminated by `case _`
		} else
		if (auto subC = cast(MixinInit)sub.val){
			ret.mixinInits ~= subC;
		} else
		if (auto subC = cast(CCNode)sub.val){
			ret.cComp ~= subC;
		} else {
			assert (false, "fix the parser pls!");
		}
	}
	return CmpErrVal!StaticSwitch(ret);
}

/// parses tokens for a Case
/// Returns: Case or error
@GFn
@Hook(TT.Case)
CmpErrVal!Case parseCase(ref TokRange toks){
	assert (toks.front.type.get!(TT.Case));
	toks.popFront;
	CmpErrVal!Expression val = P.parseExpr!(DEF_P, Expression)(toks);
	if (val.isErr)
		return CmpErrVal!Case(val.err);
	Case ret;
	// check if is default
	if (cast(IdentExpr)val.val &&
			(cast(IdentExpr)(val.val)).ident == "_")
		ret = new CaseDef;
	else
		ret = new Case;
	ret.val = val.val;
	CmpErrVal!Block body = P.parse!Block(toks);
	if (body.isErr)
		return CmpErrVal!Case(body.err);
	ret.body = body.val;
	return CmpErrVal!Case(ret);
}

/// parses tokens for a Case
/// Returns: Case or error
@GFn
@Hook(TT.Case)
CmpErrVal!StaticCase parseStaticCase(ref TokRange toks){
	assert (toks.front.type.get!(TT.Case));
	toks.popFront;
	CmpErrVal!Expression val = P.parseExpr!(DEF_P, Expression)(toks);
	if (val.isErr)
		return CmpErrVal!StaticCase(val.err);
	StaticCase ret;
	// check if is default
	if (cast(IdentExpr)val.val &&
			(cast(IdentExpr)(val.val)).ident == "_")
		ret = new StaticCaseDef;
	else
		ret = new StaticCase;
	ret.val = val.val;
	CmpErrVal!AnyBlock body = P.parse!AnyBlock(toks);
	if (body.isErr)
		return CmpErrVal!StaticCase(body.err);
	ret.body = body.val;
	return CmpErrVal!StaticCase(ret);
}

/// To make Expression behave as Statement
@GFn
/*@Hook(TT.OpPre) @Hook(TT.Identifier)
@Hook(TT.Struct) @Hook(TT.Union) @Hook(TT.Fn)
@Hook(TT.Intrinsic) @Hook(TT.True) @Hook(TT.False)*/
CmpErrVal!Expression parseExprAsStatement(ref TokRange toks){
	CmpErrVal!Expression ret = P.parseExpr!(MAX_P, Expression)(toks);
	if (ret.isErr)
		return ret;
	if (!P.expectPop!(TT.Semicolon)(toks))
		return CmpErrVal!Expression(errUnxpTok(toks.front,
					[TT.Semicolon.stringof]));
	return ret;
}

/// parses tokens for a StructAnon
/// Returns: StructAnon or error
@GFn
@Expr
@Hook(TT.Struct)
CmpErrVal!StructAnon parseStructAnon(ref TokRange toks){
	assert(toks.front.type.get!(TT.Struct));
	toks.popFront;
	StructAnon ret = new StructAnon;
	CmpErrVal!Struct val = P.parse!Struct(toks);
	if (val.isErr)
		return CmpErrVal!StructAnon(val.err);
	ret.val = val.val;
	return CmpErrVal!StructAnon(ret);
}

/// parses tokens for a NamedUnionAnon
/// Returns: NamedUnionAnon or error
@GFn
@Expr
@Hook(TT.Union)
CmpErrVal!UnionAnon parseUnionAnon(ref TokRange toks){
	assert(toks.front.type.get!(TT.Union));
	toks.popFront;
	UnionAnon ret = new UnionAnon;
	CmpErrVal!Union val = P.parse!Union(toks);
	if (val.isErr)
		return CmpErrVal!UnionAnon(val.err);
	ret.val = val.val;
	return CmpErrVal!UnionAnon(ret);
}

/// parses anonymous function
/// Returns: FnAnonExpr or error
@GFn
@Hook(TT.Fn)
@Expr
CmpErrVal!FnAnonExpr parseFnAnon(ref TokRange toks){
	assert(toks.front.type.get!(TT.Fn));
	toks.popFront;
	FnAnonExpr ret = new FnAnonExpr;

	// params
	CmpErrVal!FParamList params = P.parse!FParamList(toks);
	if (params.isErr)
		return CmpErrVal!FnAnonExpr(params.err);
	ret.params = params.val;

	// expect ->
	if (!P.expectPop!(TT.OpArrow)(toks))
		return CmpErrVal!FnAnonExpr(errUnxpTok(toks.front, [TT.OpArrow.stringof]));

	CmpErrVal!Expression expr = P.parseExpr!(DEF_P, Expression)(toks);
	if (expr.isErr)
		return CmpErrVal!FnAnonExpr(expr.err);
	ret.body = expr.val;
	return CmpErrVal!FnAnonExpr(ret);
}

/// parses tokens for a Comma Expression
/// Returns: Expression or error
@GFn
@Bin!","
CmpErrVal!CommaExpr parseCommaExpr(ref TokRange toks, Expression prev){
	assert(toks.front.type.get!(TT.OpComma));
	toks.popFront;
	assert(prev);
	CommaExpr ret = cast(CommaExpr) prev;
	if (ret is null){
		ret = new CommaExpr;
		ret.exprs = [prev];
	}
	CmpErrVal!Expression rhs = P.parseExpr!(MAX_P, Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!CommaExpr(rhs.err);
	ret.exprs ~= rhs.val;
	return CmpErrVal!CommaExpr(ret);
}

/// parses tokens for OpRefPost
/// Returns: OpRefPost or error
@GFn @Post!"@"
CmpErrVal!OpRefPost parseOpRefPost(ref TokRange toks, Expression prev){
	toks.popFront;
	OpRefPost ret = new OpRefPost;
	ret.operand = prev;
	return CmpErrVal!OpRefPost(ret);
}

/// parses tokens for OpIncPost
/// Returns: OpIncPost or error
@GFn @Post!"++"
CmpErrVal!OpIncPost parseOpIncPost(ref TokRange toks, Expression prev){
	toks.popFront;
	OpIncPost ret = new OpIncPost;
	ret.operand = prev;
	return CmpErrVal!OpIncPost(ret);
}

/// parses tokens for OpDecPost
/// Returns: OpDecPost or error
@GFn @Post!"--"
CmpErrVal!OpDecPost parseOpDecPost(ref TokRange toks, Expression prev){
	toks.popFront;
	OpDecPost ret = new OpDecPost;
	ret.operand = prev;
	return CmpErrVal!OpDecPost(ret);
}

/// parses tokens for OpQPost
/// Returns: OpQPost or error
@GFn @Post!"?"
CmpErrVal!OpQPost parseOpQPost(ref TokRange toks, Expression prev){
	toks.popFront;
	OpQPost ret = new OpQPost;
	ret.operand = prev;
	return CmpErrVal!OpQPost(ret);
}

/// parses tokens for OpDotsPost
/// Returns: OpDotsPost or error
@GFn @Post!"..."
CmpErrVal!OpDotsPost parseOpDotsPost(ref TokRange toks, Expression prev){
	toks.popFront;
	OpDotsPost ret = new OpDotsPost;
	ret.operand = prev;
	return CmpErrVal!OpDotsPost(ret);
}

/// parses tokens for OpIsPre
/// Returns: OpIsPre or error
@GFn @Pre!"is"
CmpErrVal!OpIsPre parseOpIsPre(ref TokRange toks){
	toks.popFront;
	OpIsPre ret = new OpIsPre;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfPre!"is", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpIsPre(rhs.err);
	ret.operand = rhs.val;
	return CmpErrVal!OpIsPre(ret);
}

/// parses tokens for OpNotIsPre
/// Returns: OpNotIsPre or error
@GFn @Pre!"!is"
CmpErrVal!OpNotIsPre parseOpNotIsPre(ref TokRange toks){
	toks.popFront;
	OpNotIsPre ret = new OpNotIsPre;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfPre!"!is", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpNotIsPre(rhs.err);
	ret.operand = rhs.val;
	return CmpErrVal!OpNotIsPre(ret);
}

/// parses tokens for OpNotPre
/// Returns: OpNotPre or error
@GFn @Pre!"!"
CmpErrVal!OpNotPre parseOpNotPre(ref TokRange toks){
	toks.popFront;
	OpNotPre ret = new OpNotPre;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfPre!"!", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpNotPre(rhs.err);
	ret.operand = rhs.val;
	return CmpErrVal!OpNotPre(ret);
}

/// parses tokens for OpRefPre
/// Returns: OpRefPre or error
@GFn @Pre!"@"
CmpErrVal!OpRefPre parseOpRefPre(ref TokRange toks){
	toks.popFront;
	OpRefPre ret = new OpRefPre;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfPre!"@", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpRefPre(rhs.err);
	ret.operand = rhs.val;
	return CmpErrVal!OpRefPre(ret);
}

/// parses tokens for OpTagPre
/// Returns: OpTagPre or error
@GFn @Pre!"#"
CmpErrVal!OpTagPre parseOpTagPre(ref TokRange toks){
	toks.popFront;
	OpTagPre ret = new OpTagPre;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfPre!"#", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpTagPre(rhs.err);
	ret.operand = rhs.val;
	return CmpErrVal!OpTagPre(ret);
}

/// parses tokens for OpConstPre
/// Returns: OpConstPre or error
@GFn @Pre!"const"
CmpErrVal!Expression parseOpConstPre(ref TokRange toks){
	toks.popFront;
	CmpErrVal!Expression rhsRes = P.parseExpr!(PrecedOfPre!"const", Expression)(toks);
	if (rhsRes.isErr)
		return CmpErrVal!Expression(rhsRes.err);
	Expression rhs = rhsRes.val;
	if (AutoExpr autoExpr = cast(AutoExpr)rhs){
		autoExpr.isConst = true;
		return CmpErrVal!Expression(autoExpr);
	}
	OpConstPre ret = new OpConstPre;
	ret.operand = rhs;
	return CmpErrVal!Expression(ret);
}

/// parses tokens for OpBitNotPre
/// Returns: OpBitNotPre or error
@GFn @Pre!"~"
CmpErrVal!OpBitNotPre parseOpBitNotPre(ref TokRange toks){
	toks.popFront;
	OpBitNotPre ret = new OpBitNotPre;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfPre!"~", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpBitNotPre(rhs.err);
	ret.operand = rhs.val;
	return CmpErrVal!OpBitNotPre(ret);
}

/// parses tokens for a (...) expression
/// Returns: Expression or error
@GFn
@Pre!"(" // )
CmpErrVal!Expression parserBracketExpr(ref TokRange toks){
	assert(toks.front.type.get!(TT.BracketOpen));
	toks.popFront;
	CmpErrVal!Expression ret = P.parseExpr!(MAX_P, Expression)(toks);
	if (ret.isErr)
		return CmpErrVal!Expression(ret.err);
	if (!P.expectPop!(TT.BracketClose)(toks))
		return CmpErrVal!Expression(errUnxpTok(toks.front,
					[TT.BracketClose.stringof]));
	return CmpErrVal!Expression(ret.val);
}

/// parses tokens for OpArrowBin
/// Returns: OpArrowBin or error
@GFn @Bin!"->"
CmpErrVal!OpArrowBin parseOpArrowBin(ref TokRange toks, Expression prev){
	toks.popFront;
	OpArrowBin ret = new OpArrowBin;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfBin!"->", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpArrowBin(rhs.err);
	ret.lhs = prev;
	ret.rhs = rhs.val;
	return CmpErrVal!OpArrowBin(ret);
}

/// parses tokens for OpCommaBin
/// Returns: OpCommaBin or error
@GFn @Bin!","
CmpErrVal!OpCommaBin parseOpCommaBin(ref TokRange toks, Expression prev){
	toks.popFront;
	OpCommaBin ret = new OpCommaBin;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfBin!",", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpCommaBin(rhs.err);
	ret.lhs = prev;
	ret.rhs = rhs.val;
	return CmpErrVal!OpCommaBin(ret);
}

/// parses tokens for OpDotBin
/// Returns: OpDotBin or error
@GFn @Bin!"."
CmpErrVal!OpDotBin parseOpDotBin(ref TokRange toks, Expression prev){
	toks.popFront;
	OpDotBin ret = new OpDotBin;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfBin!".", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpDotBin(rhs.err);
	ret.lhs = prev;
	ret.rhs = rhs.val;
	return CmpErrVal!OpDotBin(ret);
}

/// parses tokens for OpQQBin
/// Returns: OpQQBin or error
@GFn @Bin!"??"
CmpErrVal!OpQQBin parseOpQQBin(ref TokRange toks, Expression prev){
	toks.popFront;
	OpQQBin ret = new OpQQBin;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfBin!"??", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpQQBin(rhs.err);
	ret.lhs = prev;
	ret.rhs = rhs.val;
	return CmpErrVal!OpQQBin(ret);
}

/// parses tokens for OpMulBin
/// Returns: OpMulBin or error
@GFn @Bin!"*"
CmpErrVal!OpMulBin parseOpMulBin(ref TokRange toks, Expression prev){
	toks.popFront;
	OpMulBin ret = new OpMulBin;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfBin!"*", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpMulBin(rhs.err);
	ret.lhs = prev;
	ret.rhs = rhs.val;
	return CmpErrVal!OpMulBin(ret);
}

/// parses tokens for OpDivBin
/// Returns: OpDivBin or error
@GFn @Bin!"/"
CmpErrVal!OpDivBin parseOpDivBin(ref TokRange toks, Expression prev){
	toks.popFront;
	OpDivBin ret = new OpDivBin;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfBin!"/", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpDivBin(rhs.err);
	ret.lhs = prev;
	ret.rhs = rhs.val;
	return CmpErrVal!OpDivBin(ret);
}

/// parses tokens for OpModBin
/// Returns: OpModBin or error
@GFn @Bin!"%"
CmpErrVal!OpModBin parseOpModBin(ref TokRange toks, Expression prev){
	toks.popFront;
	OpModBin ret = new OpModBin;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfBin!"%", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpModBin(rhs.err);
	ret.lhs = prev;
	ret.rhs = rhs.val;
	return CmpErrVal!OpModBin(ret);
}

/// parses tokens for OpAddBin
/// Returns: OpAddBin or error
@GFn @Bin!"+"
CmpErrVal!OpAddBin parseOpAddBin(ref TokRange toks, Expression prev){
	toks.popFront;
	OpAddBin ret = new OpAddBin;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfBin!"+", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpAddBin(rhs.err);
	ret.lhs = prev;
	ret.rhs = rhs.val;
	return CmpErrVal!OpAddBin(ret);
}

/// parses tokens for OpSubBin
/// Returns: OpSubBin or error
@GFn @Bin!"-"
CmpErrVal!OpSubBin parseOpSubBin(ref TokRange toks, Expression prev){
	toks.popFront;
	OpSubBin ret = new OpSubBin;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfBin!"-", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpSubBin(rhs.err);
	ret.lhs = prev;
	ret.rhs = rhs.val;
	return CmpErrVal!OpSubBin(ret);
}

/// parses tokens for OpLSBin
/// Returns: OpLSBin or error
@GFn @Bin!"<<"
CmpErrVal!OpLSBin parseOpLSBin(ref TokRange toks, Expression prev){
	toks.popFront;
	OpLSBin ret = new OpLSBin;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfBin!"<<", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpLSBin(rhs.err);
	ret.lhs = prev;
	ret.rhs = rhs.val;
	return CmpErrVal!OpLSBin(ret);
}

/// parses tokens for OpRSBin
/// Returns: OpRSBin or error
@GFn @Bin!">>"
CmpErrVal!OpRSBin parseOpRSBin(ref TokRange toks, Expression prev){
	toks.popFront;
	OpRSBin ret = new OpRSBin;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfBin!">>", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpRSBin(rhs.err);
	ret.lhs = prev;
	ret.rhs = rhs.val;
	return CmpErrVal!OpRSBin(ret);
}

/// parses tokens for OpEqBin
/// Returns: OpEqBin or error
@GFn @Bin!"=="
CmpErrVal!OpEqBin parseOpEqBin(ref TokRange toks, Expression prev){
	toks.popFront;
	OpEqBin ret = new OpEqBin;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfBin!"==", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpEqBin(rhs.err);
	ret.lhs = prev;
	ret.rhs = rhs.val;
	return CmpErrVal!OpEqBin(ret);
}

/// parses tokens for OpNotEqBin
/// Returns: OpNotEqBin or error
@GFn @Bin!"!="
CmpErrVal!OpNotEqBin parseOpNotEqBin(ref TokRange toks, Expression prev){
	toks.popFront;
	OpNotEqBin ret = new OpNotEqBin;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfBin!"!=", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpNotEqBin(rhs.err);
	ret.lhs = prev;
	ret.rhs = rhs.val;
	return CmpErrVal!OpNotEqBin(ret);
}

/// parses tokens for OpGrEqBin
/// Returns: OpGrEqBin or error
@GFn @Bin!">="
CmpErrVal!OpGrEqBin parseOpGrEqBin(ref TokRange toks, Expression prev){
	toks.popFront;
	OpGrEqBin ret = new OpGrEqBin;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfBin!">=", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpGrEqBin(rhs.err);
	ret.lhs = prev;
	ret.rhs = rhs.val;
	return CmpErrVal!OpGrEqBin(ret);
}

/// parses tokens for OpLsEqBin
/// Returns: OpLsEqBin or error
@GFn @Bin!"<="
CmpErrVal!OpLsEqBin parseOpLsEqBin(ref TokRange toks, Expression prev){
	toks.popFront;
	OpLsEqBin ret = new OpLsEqBin;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfBin!"<=", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpLsEqBin(rhs.err);
	ret.lhs = prev;
	ret.rhs = rhs.val;
	return CmpErrVal!OpLsEqBin(ret);
}

/// parses tokens for OpGrBin
/// Returns: OpGrBin or error
@GFn @Bin!">"
CmpErrVal!OpGrBin parseOpGrBin(ref TokRange toks, Expression prev){
	toks.popFront;
	OpGrBin ret = new OpGrBin;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfBin!">", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpGrBin(rhs.err);
	ret.lhs = prev;
	ret.rhs = rhs.val;
	return CmpErrVal!OpGrBin(ret);
}

/// parses tokens for OpLsBin
/// Returns: OpLsBin or error
@GFn @Bin!"<"
CmpErrVal!OpLsBin parseOpLsBin(ref TokRange toks, Expression prev){
	toks.popFront;
	OpLsBin ret = new OpLsBin;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfBin!"<", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpLsBin(rhs.err);
	ret.lhs = prev;
	ret.rhs = rhs.val;
	return CmpErrVal!OpLsBin(ret);
}

/// parses tokens for OpColonBin
/// Returns: OpColonBin or error
@GFn @Bin!":"
CmpErrVal!OpColonBin parseOpColonBin(ref TokRange toks, Expression prev){
	toks.popFront;
	OpColonBin ret = new OpColonBin;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfBin!":", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpColonBin(rhs.err);
	ret.lhs = prev;
	ret.rhs = rhs.val;
	return CmpErrVal!OpColonBin(ret);
}

/// parses tokens for OpIsBin
/// Returns: OpIsBin or error
@GFn @Bin!"is"
CmpErrVal!OpIsBin parseOpIsBin(ref TokRange toks, Expression prev){
	toks.popFront;
	OpIsBin ret = new OpIsBin;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfBin!"is", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpIsBin(rhs.err);
	ret.lhs = prev;
	ret.rhs = rhs.val;
	return CmpErrVal!OpIsBin(ret);
}

/// parses tokens for OpNotIsBin
/// Returns: OpNotIsBin or error
@GFn @Bin!"!is"
CmpErrVal!OpNotIsBin parseOpNotIsBin(ref TokRange toks, Expression prev){
	toks.popFront;
	OpNotIsBin ret = new OpNotIsBin;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfBin!"!is", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpNotIsBin(rhs.err);
	ret.lhs = prev;
	ret.rhs = rhs.val;
	return CmpErrVal!OpNotIsBin(ret);
}

/// parses tokens for OpBitAndBin
/// Returns: OpBitAndBin or error
@GFn @Bin!"&"
CmpErrVal!OpBitAndBin parseOpBitAndBin(ref TokRange toks, Expression prev){
	toks.popFront;
	OpBitAndBin ret = new OpBitAndBin;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfBin!"&", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpBitAndBin(rhs.err);
	ret.lhs = prev;
	ret.rhs = rhs.val;
	return CmpErrVal!OpBitAndBin(ret);
}

/// parses tokens for OpBitOrBin
/// Returns: OpBitOrBin or error
@GFn @Bin!"|"
CmpErrVal!OpBitOrBin parseBitOrBin(ref TokRange toks, Expression prev){
	toks.popFront;
	OpBitOrBin ret = new OpBitOrBin;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfBin!"|", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpBitOrBin(rhs.err);
	ret.lhs = prev;
	ret.rhs = rhs.val;
	return CmpErrVal!OpBitOrBin(ret);
}

/// parses tokens for OpBitXorBin
/// Returns: OpBitXorBin or error
@GFn @Bin!"^"
CmpErrVal!OpBitXorBin parseOpBitXorBin(ref TokRange toks, Expression prev){
	toks.popFront;
	OpBitXorBin ret = new OpBitXorBin;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfBin!"^", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpBitXorBin(rhs.err);
	ret.lhs = prev;
	ret.rhs = rhs.val;
	return CmpErrVal!OpBitXorBin(ret);
}

/// parses tokens for OpAndBin
/// Returns: OpAndBin or error
@GFn @Bin!"&&"
CmpErrVal!OpAndBin parseOpAndBin(ref TokRange toks, Expression prev){
	toks.popFront;
	OpAndBin expr = new OpAndBin;
	expr.pos = Location(toks.front.line, toks.front.col);
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfBin!"&&", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpAndBin(rhs.err);
	expr.lhs = prev;
	expr.rhs = rhs.val;
	return CmpErrVal!OpAndBin(expr);
}

/// parses tokens for OpOrBin
/// Returns: OpOrBin or error
@GFn @Bin!"||"
CmpErrVal!OpOrBin parseOpOrBin(ref TokRange toks, Expression prev){
	toks.popFront;
	OpOrBin expr = new OpOrBin;
	expr.pos = Location(toks.front.line, toks.front.col);
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfBin!"||", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpOrBin(rhs.err);
	expr.lhs = prev;
	expr.rhs = rhs.val;
	return CmpErrVal!OpOrBin(expr);
}

/// parses tokens for OpAssignBin
/// Returns: OpAssignBin or error
@GFn @Bin!"="
CmpErrVal!OpAssignBin parseOpAssignBin(ref TokRange toks, Expression prev){
	toks.popFront;
	OpAssignBin ret = new OpAssignBin;
	CmpErrVal!Expression rhs = P.parseExpr!(PrecedOfBin!"=", Expression)(toks);
	if (rhs.isErr)
		return CmpErrVal!OpAssignBin(rhs.err);
	ret.lhs = prev;
	ret.rhs = rhs.val;
	return CmpErrVal!OpAssignBin(ret);
}

/// parses tokens for OpAssignAddBin
/// Returns: OpAssignAddBin or error
@GFn
@Bin!"+="
@Bin!"-="
@Bin!"*="
@Bin!"/="
@Bin!"%="
@Bin!"&="
@Bin!"|="
@Bin!"^="
CmpErrVal!OpAssignBin parseOpAssignAddBin(ref TokRange toks,
		Expression prev){
	string op = toks.front.token;
	Location pos = Location(toks.front.line, toks.front.col);
	toks.popFront;
	// HACK: assuming all compound assignment statements are same precedence
	CmpErrVal!Expression rhsRes = P.parseExpr!(PrecedOfBin!"+=", Expression)(toks);
	if (rhsRes.isErr)
		return CmpErrVal!OpAssignBin(rhsRes.err);
	Expression rhsVal = (rhsRes.val);
	OpAssignBin ret = new OpAssignBin;
	OpBinExpr valExpr;
	final switch (op){
		case "+=":
			valExpr = new OpAddBin;
			break;
		case "-=":
			valExpr = new OpSubBin;
			break;
		case "*=":
			valExpr = new OpMulBin;
			break;
		case "/=":
			valExpr = new OpDivBin;
			break;
		case "%=":
			valExpr = new OpModBin;
			break;
		case "&=":
			valExpr = new OpBitAndBin;
			break;
		case "|=":
			valExpr = new OpBitOrBin;
			break;
		case "^=":
			valExpr = new OpBitXorBin;
			break;
	}
	valExpr.pos = pos;
	valExpr.lhs = prev;
	valExpr.rhs = rhsVal;
	ret.lhs = prev;
	ret.rhs = valExpr;
	return CmpErrVal!OpAssignBin(ret);
}

/// parses tokens for a OpCallExpr
/// Returns: OpCallExpr or error
@GFn
@Bin!"(" // )
CmpErrVal!OpCallExpr parseOpCallExpr(ref TokRange toks, Expression prev){
	assert(toks.front.type.get!(TT.OpCall));
	toks.popFront;
	OpCallExpr ret = new OpCallExpr;
	ret.callee = prev;
	while (!P.expectPop!(TT.BracketClose)(toks)){
		CmpErrVal!Expression arg = P.parseExpr!(DEF_P, Expression)(toks);
		if (arg.isErr)
			return CmpErrVal!OpCallExpr(arg.err);
		ret.params ~= arg.val;
		P.expectPop!(TT.OpComma)(toks);
	}
	return CmpErrVal!OpCallExpr(ret);
}

/// parses tokens for a OpIndexExpr
/// Returns: OpIndexExpr or error
@GFn
@Bin!"[" // ]
CmpErrVal!OpIndexExpr parseOpIndexExpr(ref TokRange toks, Expression prev){
	assert(toks.front.type.get!(TT.OpIndex));
	toks.popFront;
	OpIndexExpr ret = new OpIndexExpr;
	ret.lhs = prev;
	while (!P.expectPop!(TT.IndexClose)(toks)){
		CmpErrVal!Expression arg = P.parseExpr!(DEF_P, Expression)(toks);
		if (arg.isErr)
			return CmpErrVal!OpIndexExpr(arg.err);
		ret.indexes ~= arg.val;
		P.expectPop!(TT.OpComma)(toks);
	}
	return CmpErrVal!OpIndexExpr(ret);
}

/// parses tokens for a BlockExpr
/// Returns: BlockExpr or error
@GFn
@Bin!"{" // }
CmpErrVal!BlockExpr parseBlockExpr(ref TokRange toks, Expression prev){
	assert(toks.front.type.get!(TT.OpCurly));
	//toks.popFront;
	BlockExpr ret = new BlockExpr;
	ret.type = prev;
	CmpErrVal!Block block = P.parse!Block(toks);
	if (block.isErr)
		return CmpErrVal!BlockExpr(block.err);
	ret.block = block.val;
	return CmpErrVal!BlockExpr(ret);
}

/// parses tokens for a IntrinsicExpr
/// Returns: IntrinsicExpr or error
@GFn
@Hook(TT.Intrinsic)
@Expr
CmpErrVal!IntrinsicExpr parseIntrinsicExpr(ref TokRange toks){
	assert(toks.front.type.get!(TT.Intrinsic));
	Tok front = toks.front;
	toks.popFront;
	IntrinsicExpr ret = new IntrinsicExpr;
	ret.name = front.token[1 .. $];

	return CmpErrVal!IntrinsicExpr(ret);
}

/// parses tokens for a StructLiteralExpr
/// Returns: StructLiteralExpr or error
@GFn
@Hook(TT.CurlyOpen)
@Expr
CmpErrVal!StructLiteralExpr parseStructLiteralExpr(ref TokRange toks){
	assert(toks.front.type.get!(TT.CurlyOpen));
	toks.popFront;
	StructLiteralExpr ret = new StructLiteralExpr;
	while (!P.expectPop!(TT.CurlyClose)(toks)){
		CmpErrVal!ASTNode sub = P.parse!(KeyVal, CCNode)(toks);
		if (sub.isErr)
			return CmpErrVal!StructLiteralExpr(sub.err);
		if (cast(KeyVal)sub.val)
			ret.keyVals ~= cast(KeyVal)sub.val;
		else
		if (cast(CCNode)sub.val)
			ret.cComp ~= cast(CCNode)sub.val;
		P.expectPop!(TT.OpComma)(toks);
	}
	return CmpErrVal!StructLiteralExpr(ret);
}

/// parses tokens for a BoolLiteralExpr
@GFn
@Hook(TT.True) @Hook(TT.False)
@Expr
CmpErrVal!BoolLiteralExpr parseBoolLiteralExpr(ref TokRange toks){
	assert(P.expect!(TT.True, TT.False)(toks));
	BoolLiteralExpr ret = new BoolLiteralExpr;
	ret.val = toks.front.type.get!(TT.True);
	toks.popFront;
	return CmpErrVal!BoolLiteralExpr(ret);
}

/// parsing tokens for LiteralScientific (Float literal)
/// Returns: LiteralFloatExpr or error
@GFn
@Hook(TT.LiteralScientific)
@Expr
CmpErrVal!LiteralFloatExpr parseLiteralScientific(ref TokRange toks){
	assert(toks.front.type.get!(TT.LiteralScientific));
	LiteralFloatExpr ret = new LiteralFloatExpr;
	string valStr = toks.front.token;
	try{
		immutable size_t eInd = valStr.countUntil('e');
		ret.val = valStr[0 .. eInd].to!double.pow(valStr[eInd + 1 .. $].to!size_t);
	} catch (Exception e){
		return CmpErrVal!LiteralFloatExpr(errLiteral(toks.front,
					format!"Error decoding integer literal: %s"(e.msg)));
	}
	return CmpErrVal!LiteralFloatExpr(ret);
}

/// parses tokens for a LiteralIntExpr
/// Returns: LiteralIntExpr or error
@GFn
@Hook(TT.LiteralInt) @Hook(TT.LiteralBinary)
@Hook(TT.LiteralHexadecimal)
@Expr
CmpErrVal!LiteralIntExpr parseLiteralIntExpr(ref TokRange toks){
	assert(P.expect!(TT.LiteralInt, TT.LiteralBinary, TT.LiteralHexadecimal)(
				toks));
	LiteralIntExpr ret = new LiteralIntExpr;
	string valStr = toks.front.token;
	// decode
	try{
		if (toks.front.type.get!(TT.LiteralHexadecimal)){
			ret.val = cast(ptrdiff_t)valStr[2 .. $].readHexadecimal();
		} else
		if (toks.front.type.get!(TT.LiteralBinary)){
			ret.val = cast(ptrdiff_t)valStr[2 .. $].readBinary();
		} else {
			ret.val = valStr.to!ptrdiff_t;
		}
	} catch (Exception e){
		return CmpErrVal!LiteralIntExpr(errLiteral(toks.front,
					format!"Error decoding integer literal: %s"(e.msg)));
	}
	toks.popFront;
	return CmpErrVal!LiteralIntExpr(ret);
}

/// parses tokens for a LiteralFloatExpr
/// Returns: LiteralFloatExpr or error
@GFn
@Hook(TT.LiteralFloat)
@Expr
CmpErrVal!LiteralFloatExpr parseLiteralFloatExpr(ref TokRange toks){
	assert(P.expect!(TT.LiteralFloat)(toks));
	LiteralFloatExpr ret = new LiteralFloatExpr;
	try{
		ret.val = toks.front.token.to!double;
	} catch (Exception e){
		return CmpErrVal!LiteralFloatExpr(errLiteral(toks.front,
					format!"Error decoding integer literal: %s"(e.msg)));
	}
	toks.popFront;
	return CmpErrVal!LiteralFloatExpr(ret);
}

/// parses tokens for a LiteralStringExpr
/// Returns: LiteralStringExpr or error
@GFn
@Hook(TT.LiteralString) @Hook(TT.LiteralStringML)
@Expr
CmpErrVal!LiteralStringExpr parseLiteralStringExpr(ref TokRange toks){
	assert(P.expect!(TT.LiteralString, TT.LiteralStringML)(toks));
	LiteralStringExpr ret = new LiteralStringExpr;
	if (toks.front.type.get!(TT.LiteralString))
		ret.val = cast(string)toks.front.token[1 .. $ - 1].strUnescape;
	else
	if (toks.front.type.get!(TT.LiteralStringML))
		ret.val = cast(string)toks.front.token[4 .. $ - 4].strUnescape;
	toks.popFront;
	return CmpErrVal!LiteralStringExpr(ret);
}

/// parses tokens for a LiteralCharExpr
/// Returns: LiteralCharExpr or error
@GFn
@Hook(TT.LiteralChar)
@Expr
CmpErrVal!LiteralCharExpr parseLiteralCharExpr(ref TokRange toks){
	assert(P.expect!(TT.LiteralChar)(toks));
	LiteralCharExpr ret = new LiteralCharExpr;
	ret.val = toks.front.token[1 .. $ - 1].strUnescape[0];
	toks.popFront;
	return CmpErrVal!LiteralCharExpr(ret);
}

/// parses tokens for a LiteralArrayExpr
/// Returns: LiteralArrayExpr or error
@GFn
@Hook(TT.IndexOpen)
@Expr
CmpErrVal!LiteralArrayExpr parseLiteralArrayExpr(ref TokRange toks){
	assert(toks.front.type.get!(TT.IndexOpen));
	toks.popFront;
	LiteralArrayExpr ret = new LiteralArrayExpr;
	while (!P.expectPop!(TT.IndexClose)(toks)){
		CmpErrVal!Expression sub = P.parseExpr!(DEF_P, Expression)(toks);
		if (sub.isErr)
			return CmpErrVal!LiteralArrayExpr(sub.err);
		ret.elements ~= sub.val;
		P.expectPop!(TT.OpComma)(toks);
	}

	return CmpErrVal!LiteralArrayExpr(ret);
}

/// parses tokens for an Expression
/// Returns: Expression or error
@GFn
@Expr
@Hook(TT.Identifier)
CmpErrVal!IdentExpr parseIdentExpr(ref TokRange toks){
	assert(toks.front.type.get!(TT.Identifier));
	IdentExpr expr;
	Tok front = toks.front;
	toks.popFront;

	if (front.type.get!(TT.Auto))
		expr = new AutoExpr;
	else
	if (front.type.get!(TT.This))
		expr = new ThisExpr;
	else
	if (front.type.get!(TT.Int))
		expr = new IntExpr;
	else
	if (front.type.get!(TT.UInt))
		expr = new UIntExpr;
	else
	if (front.type.get!(TT.Float))
		expr = new FloatExpr;
	else
	if (front.type.get!(TT.Char))
		expr = new CharExpr;
	else
	if (front.type.get!(TT.String))
		expr = new StringExpr;
	else
	if (front.type.get!(TT.Bool))
		expr = new BoolExpr;
	else
		expr = new IdentExpr;
	expr.ident = front.token;
	expr.pos = Location(front.line, front.col);

	return CmpErrVal!IdentExpr(expr);
}

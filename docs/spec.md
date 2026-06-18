# Comments

Comments can be added using `//`:

```
// this is a comment
```

Multi line comments can be written by enclosing them in between `/*` and `*/`:

```
/*multiline
comment
*/
```

Use `///` comments for writing documentation, before any declaration:
```
/// position on x axis
var int posX;
```

If the very first line in the file begins with a `#`, that line is ignored,
this is to make it possible to put a shebang on UNIX systems:

```
#!/usr/bin/alis
// now this file can be run by `./scriptFileName`
```

---

# Functions

```
fn NAME PARAM_LIST -> EXPR;
```

- `NAME` (optional) is the name of the function
- `PARAM_LIST` is list of parameters. See below for syntax
- `EXPR` is the expression to be evaluated. Usually, this will be:
    `RETURN_TYPE{ function_body; return X; }` where `RETURN_TYPE` can be `void`

## `PARAM_LIST`

Parameters are defined as either:

- `()` - no parameters
- `name` or `(name)` - in case of single parameter, whose type can be inferred
- `(name, name)` - multiple parameters, types inferred
- `(type name, type name)` - multiple parameters, typed

The parantheses around parameters are required only in these cases:

- there are more than one paramters: `(x, y) -> ...;`
- the only parameter has its type explicitly specified: `(int x) -> ...;`
- there are no parameters: `() -> ...;`

## Function Declaration

A function declaration, separate from the definition, can be provided as:

```
fn NAME PARAM_LIST -> RETURN_TYPE;
```

## Default parameters

A parameter can be assigned a default value if it is either the last paramter,
or if every other parameter after it too has a default value:

```
fn foo(int a = 0, int b = 1) -> int; // valid
fn bar(int a, int b = 1) -> int; // valid
fn baz(int a = 0, int b) -> int; // invalid
```

While calling a function, to use the default value for a parameter:

```
fn foo(int a = 1, int b = 5) -> void;
foo(0); // a=1, b=default(5)
```

## Anonymous Functions

See functions syntax above. A function is made anonymous by omitting the name:

```
fn PARAM_LIST -> EXPR;
```

Example:

```
fn (int i) -> i + 1;
```

## Returning From Functions

```
return [RETURN_VALUE];
```

The `RETURN_VALUE` must be either of the return type, or must be implicitly
cast-able. In case of functions that do not return anything, it can be just
`return;`

## Function Calls

Function calls are made through the `()` operator like:

```
fnName(funcArg0, funcArg1, ...);
```

or in case of no arguments:

```
fnName();
// or
fnName;
```

The first argument(s) to a function call can also be passed using the `.`
operator:

```
fn sum(int a, int b) -> int{
    return a + b;
}

// all of the following are equivalent
sum(5, 5);
5.sum(5);
(5, 5).sum();
(5, 5).sum;
```

The one case where `()` is necessary for function call is when using the prefix
`@` operator:

```
writeln(@bar); // bar not called
writeln(bar); // bar called
```

---

# Unit Tests

Tests can be written as:

```
utest [NAME_STR]{
    // test body
}
```

`NAME_STR` is an optional string literal, used as a name for this test.

the test body is a sequence of statements. Returning any error type from a test
will be used to check if the test failed or not.

---

# Variables

## Variable Declaration

Variables can be declared like:

```
var TYPE var0, var1, var2;
```

- `TYPE` is the data type of the variables
- `var0`, `var1`, `var2` are the names of the variables. Comma separated.

Value assignment can also be done in the variable declaration statement like:

```
var int var0 = 12, var1 = 24;
```

## Variable Assignment

Variables can be assigned using the `=` operator:

```
variable = value;
```

## Variable Scope

Variables are only available inside the scope they are declared in.
In the code below:

```
var int someGlobalVar;
pub fn main() -> void{
    var int i = someGlobalVar;
    {
        var int j = i;
    }
    i = j; // error, j not accessible here
}
```

## Constants

Constants can be defined through the usual `var` syntax:

```
var const int FIFTEEN = 15;
```

Or use the short syntax:

```
const int FIFTEEN = 15;
```

---

# `_` identifiers

`_` can be used as a "discard" identifier. Anything named `_` will be created,
but inaccessible. For example:

```
var int _; // create an int, that cannot be accessed
var int _; // create another such int

fn main(string[] _) -> void{
    // receive string[] parameter, do not use it
}

for (i; auto _; range){
    // iterate range, ignoring the values, just keep the counter
}
```

## `_` identifiers in function parameter

If a function receives any parameter named `_`, rather than calling it with a
value, you can call it via the type:

```
fn foo(string[] _, int x) -> ...{...}

foo(string[], 5); // is valid
string[].foo(5); // also valid

struct Pos{ int x; int y; }
fn fromString(Pos _, string s) -> Pos{...}

Pos p = Pos.fromString("5,5"); // valid
```

---

# Data Types

Integers:

- `int` - largest supported signed integer (usually 64 or 32 bits)
- `uint` - largest supported unsigned integer (usually 64 or 32 bits)
- `$int(X)` - signed integer of X bits
- `$uint(X)` - unsigned integer of X bits

Floats:

- `float` - largest supported floating point number
- `$float(X)` - floating point number of X bits

Characters:

- `char` - an 8 bit character
- `$char` - an 8 bit character // TODO

Others:

- `void` - incapable of storing any data, equivalent to `struct {}`
- `bool` - a `true` or `false`
- `string` - the same as a `$slice(const char)`
- `auto` - makes use of compiler's type inference to auto-detect a type.
- `@X` - reference to any of the above
- `@fn ARG_TYPES -> RETURN_TYPE` - reference to a function
- `const X` - a constant of type X. Value cannot change after creation
- `$array(X)` - array of type X
- `$slice(X)` - slice of an array of type X

## `int` (and other integers)

This can be written as series (or just one) digit(s).

Can be written as:

- Binary - `0B1100` or `0b1100` - for `12`
- Hexadecimal - `0xFF` - for `15`
- Series of `[0-9]+` digits
- scientific notation - `XeY`, where `X` must be a decimal number, it cannot be
    written in Binary or Hexadecimal, and `Y` must be an integer. Since this is
    an Integer, the resulting number must not have any non-zero digits right of
    the decial point.

`int` is initialised as `0`.

## floating points

Digits with a single `.` between them is read as a double.
`5` is an int, but `5.0` is a double.

A floating point number can also be written in scientific notation (see above).

initialised as `0.0`

## `char`

This is written by enclosing a single character within a pair of apostrophes:

`'c'` for example, or `'\t'` tab character.

initialised as ascii code `0`

## `bool`

A `true` (1) or a `false` (0).

While casting from `int`, a non zero value is read as a `true`, zero as `false`.

initialised as `false`

## `@X` references

These are pointers to data. A reference must always be pointing to a valid data,
there are no nulls.

```
var int i = 0;
var @int r; // error, not initialised
var @int r = @i;
r = 2;
i.writeln; // 2
r@.writeln; // 2

var int j = 0;
r = @j; // reassign is fine
r@ = 1;
r@.writeln; // 1
j.writeln; // 1
i.writeln; // 2
```

To get reference to something, use the pre`@` operator: `@a`
To dereference a reference, use the post`@` operator: `a@`

## `auto` variables

The `auto` keyword can be used to infer types:

```
var auto x = something;
```

## `$array(X)`

An array type provides the following operations:

- Resize (change length): `$arrLen(A, l)`. This intrinsic results in a 
    runtime function call, that resizes array `A` to length `l`
- implicit cast to `$slice(X)`
- Get Length: `$arrLen(A)`. This intrinsics tells length of array or slice,
    in number of elements it can hold.
- Get Element: `$arrInd(A, i)`. Gets element at `i`th index in `A` array or
    slice.

## `$slice(X)`

This should be aliased to `X[]` in the standard library.

A slice provides the same indexed read (and optional write) functionality as an
array, but without the resizing capability. All arrays are slices, but all
slices are not arrays.

A "static" slice can be written as `[...]` where the `...` is a comma separated
list of elements. This slice will be of type `$slice(const X)`. However it can
be used to initialize arrays:

```
var $array(int) a = [1, 2, 3];
var $slice(int) s = a; // all arrays are valid slices
```

The standard library will be responsible for providing following operations on
slices:

- `S[i]` - Get reference to `i-th` element of slice `S`
- `S.length` - Get length of slice `S`
- `S[i, j]` - Get a sub-slice of this slice, starting from index `i`, up till,
    but excluding, index `j`

## `string`

Strings in ALiS are equivalent to `$slice(const char)`, i.e:

- They cannot grow in size
- Their contents cannot be changed

Where the above limitations cause issues, it is suggested to instead use either
of the following:

- `$slice(char)` - for when you need to be able to modify the content
- `$array(char)` - for when you need to be able to append

Strings can be written as text enclosed within quotation marks:

```
"this is a string"
```

The `\` backslash can be used to escape the following characters:

- `\"` - a quotation mark `"`
- `\t` - tab
- `\n` - newline
- `\r` - carriage return
- `\b` - backspace
- `\\` - backslash `\\`
- `\'` - apostrophe `'`

The above representation does not allow for multi line strings, instead, use
the triple quotation marks syntax:

```
"""
string
here
"""
```

The string content starts at the line _after_ the opening `"""`, and ends at
the line before the `"""`:

```
"""
Hello
 World
"""
// is equivalent to:
"Hello\n World"
```

---

# Structs

These can be used to store multiple values of varying or same data types.
They also act as namespaces.

They are defined like:

```
struct STRUCT_NAME{
    [ipub|pub] TYPE NAME [ = INIT_VALUE];
    [ipub|pub] TYPE NAME [ = INIT_VALUE] , NAME_2 [ = INIT_VALUE];
    [ipub|pub] TYPE; // for when TYPE is a struct or union
    [ipub|pub] alias [X] = [Y];
}
```

By default, all members inside a struct are private.

## Anonymous Structs

A struct can be created, and immediately used, without being given a type name:

```
struct { MEMBERS }
```

`struct { MEMBERS }` is treated as an expression, that evaluates to a
data type.

Anonymous structs have all members as public, and visibility cannot be changed.

## Equivalence

Structs defined through the `struct NAME{...}` syntax are always unique:

```
struct Foo{ string a; int i; }
struct Bar{ string a; int i; }
var Foo foo;
var Bar bar;
foo = bar; // error, incompatible types
bar = foo; // error, incompatible types
```

Anonymous structs, can be implicitly casted to any other struct type, as long
as the destination type is a superset of the source type. If the destination
type has any additional members, those must be auto-initializable.

```
struct Foo{ int i; }
alias Bar = struct { int i; };
alias Baz = struct { int i; };
var Foo foo;
var Bar bar;
var Baz baz;

foo = bar; // valid
bar = baz; // valid
bar = foo; // invalid
```

## `this` alias in struct

Having `X.this` alias, where X is a struct, will add a fallback member to do
operations on rather than the struct itself. `this` can only be an alias, not
directly a member:

```
struct Length{
    int len = 0;
    string unit = "cm";
    alias this = len;
}
var Length len = 0; // Length = int is error, so assigns to the int member
len = 1;
writeln(len + 5); // Length + int is not implemented, evaluates to len.len + 5
writeln(len.unit); // prints "cm"
```

This works by allowing implicit conversions of the struct type into the aliased
member's type.

## Constructing Structs

Structs can be constructed as:

```
struct User{
    string username;
    string passhash;
}

var User u = {username = "whoami"}; // passhash defaults to zero length
```

Only members that are accessible from the current scope can be passed to
constructor:

```
struct User{
    pub string username;
    string passhash;
}

// other file:
import user;
var User u0 = {username = "abcd"}; // valid
var User u1 = {passhash = "1234"}; // invalid
```

A member's values can be omitted, only if they can be auto-initialized.

## Key-Value Parameters to Functions

```
fn foo(struct { string aa = "aa"; int x = 5; } params) -> void;

foo({aa = "bb"}); // x defaults to 5
```

---

# Unions

Unions store one of the members at a time, along with a tag, indicating which
member is currently stored:

```
union Name{
    [pub] TYPE NAME;
    [pub] TYPE; // for when type is struct or union
    [pub] alias X = Y;
}
```

Example:

```
union Val{
    int i = 0;
    float f;
    string s;
}
```

Example:

```
struct User{
    string username;
    union {
        void admin;
        void moderator;
        void user;
        struct {
            int loginAttempts = int.max;
            string ipAddr = "127.0.0.1";
        } loggedOut;
    };
}
```

This is a User struct, where the username is always stored, along with one of:

- nothing - in case of `admin`
- nothing - in case of `moderator`
- nothing - in case of `user`
- `loginAttempts` and `ipAddr` - in case of `loggedOut`

Similar to structs, anonymous unions can also be created.

Same equivalence rules as structs apply.

Same rules regarding `this` member as struct apply.

## Default Member

A union can be assigned a default member. The default member at
initialization can be denoted by assigning a default value to it. For example:

```
union Foo{
    void bar = void.$init; // bar is default
    int baz;
}

union Num{
    int i;
    float f = float.$init; // f is default
}
```

## Unnamed Unions

_Not to be confused with anonymous unions_

A union is an unnamed union if:

- For every member, the type cannot be implicitly casted to another member's
    type
- Every member is unnamed
- Every member is public (unnamed members imply this automatically)

Unnamed unions do not require a default value for a member, instead relying
on the value being provided during construction.

Example:

```
union Foo{ string; int; }
var Foo f = "hello"; // unnamed unions get opCast for free
```

Unnamed unions do not follow the regular equivalence rules:

```
union Foo { string; int; }
union Bar { int; string; }
union Baz { int; string; float; }
```

`Foo` and `Bar` are the same types, but `Baz` is not.

This can be used as:

```
fn foo(...) -> union { string; int; } {
    // ...
}
```

## Reading tag

The `unionIs(U)` intrinsic can be used to check if a union currently stores a
tag:

```
union Foo { string bar; int baz = 0; }
var Foo f;

$unionIs(f.bar); // whether f is .bar
$unionIs(f.string); // whether f stores the only member of type string

is f.bar; // whether f is .bar
is f.string; // whether f stores the only member of type string
```

Checking via the type instead of member name is only possible if the type of
every member is distinct.

In case of `this` member, following is also possible:

```
union Foo{
    void bar = void.$init;
    int bar;
    alias this = bar;
}
var Foo f;
$unionIs(f) == $unionIs(f.bar); // true
is f == is f.bar;
```

It is a compiler error to read a union member where it is not clear if that
member is stored:

```
union Foo{ int i = 0; string s; f32 f; }
fn bar() -> void{
    var Foo f = // get Foo from somewhere
    f.s.writeln; // error
    if (is f.s)
        f.s.writeln; // no error

    f.i.writeln; // error
    if (is f.s || is f.f)
        return;
    f.i.writeln; // no error
}
```

## Constructing Unions

Unions have multiple constructors, for each member. However if for some type
`T`, there are multiple members, there will be no constructor.

Example:

```
// file module.alis
union Foo{
    pub int i = 0; // default
    pub string s;
    pub struct {
        f64 x, y;
    } pos;
    int k;
}

Foo(); // fine, default i = 0
Foo(0); // error: int matches for i and k
Foo("hello"); // fine, string matches only s
Foo({x = 5, y = 6}); // fine, matches pos

// file main.alis
import module;
Foo(5); // fine, k is inaccessible, leaving i the only int
```

Alternatively, Unions can be constructed using value of type anonymous struct,
if the struct has only one member. This is not possible for unnamed unions:

```
union Foo { string s; int i = 0; };
var Foo a = {s = "abcd"};
var Foo b = {i = 5};
```

---

# Enums

Enum can be used to group together constants of the same base data type.

Enums are defined like:

```
enum TYPE EnumName{
    member0 [= val0],
    member1 [= val1],
    member2 [= val1], // same value multiple times is allowed
}
```

- `TYPE` is the base data type, `auto` is allowed
- `EnumName` is the name for this enum
- specifying values for members is optional

Example:

```
enum int ErrorType{
    FileNotFound = 1, // default value is first one
    InvalidPath = 1 << 1, // constant expression is allowed
    PermissionDenied = 4
}
```

An enum's member's value can be read as: `EnumName.MemberName`, using the
member selector operator.

Enums act as data types:

```
var ErrorType err; // initialised to FileNotFound
// or
var auto err = ErrorType.FileNotFound;
```

An enum can exist by itself, with or without a value:

```
enum auto Foo = 5;
enum auto Bar; // Bar can never be instantiated, but is a valid type
```

## Constants

The `enum` keyword can be used to create constants that are evaluated compile
time as follows:

```
enum int U8MASK = (1 << 4) - 1; // evaluated at compile time
```

These are different from regular constants, they are inlined wherever used,
and themselves do not occupy any memory.

---

# Aliases

`alias` keyword can be used to provide alternative identifiers:

```
struct Position{ // struct is private
    pub int x, y;
}

pub alias Coordinate = Position; // Coordinate is publically accessible
```

Additionally, it can be used to alias to expressions:

```
alias X = f() + 5;
X.writeln;
X.writeln;
```

In this example, `f() + 5;` is evaluated 2 times.

---

# `TYPE{...}` Expressions

Expressions written in as `DATA_TYPE { ... }` can be used to execute statements
that evaluate to a single value, of type `DATA_TYPE`:

```
5 + int{
        // some code
        return someInt
    } + 10;
```

These cannot be used everywhere, this type of expression will usually need to
be wrapped in parenthesis.

---

# Attributes

The `#` prefix operator can be used to tag definitions. 

Prefix the definition (after the `pub` or `ipub`, if in global scope):

```
#Tag fn foo(#Xyz int i) -> void;
pub #Bar struct Baz{}
```

Any value or data type is a valid tag:

```
enum auto Xyz;

pub #Xyz fn foo() -> void;
#"hello" struct Bar{}
```

## Intrinsics

The compiler provides following intrinsics for working with attributes:

- `$attrsOf(X)` - Gets sequence of all attributes of all types for symbol `X`
- `$byAttrs(X, A)` - Gets all symbols that are children of `X`, which can be
    a module, or any symbol that itself can contain symbols with Attributes. Only
    gets the symbols with attributes that: match `A`, or are of type `A`,
    depending on whether `A` is a value, or a type.

---

# Modules

Each file is a module.

The `import` keyword can be used to instantiate a module.
A module is similar to a struct, except:

1. only 1 instance of a module can exist, created the first time `import` is
    called
2. private members inside a module are not accessible outside

Import Expression:

```
import MODULE_NAME;
import MODULE_NAME, MODULE_NAME;
import MODULE_NAME as x;
import MODULE_NAME as y, MODULE_NAME as z;
```

To expose public members of an imported module:

```
pub import MODULE_NAME;
```

## Visibility

All members are by default private, and only accessible inside current scope.

The `pub` keyword can be prefixed to make a member public:

```
pub struct SomeStruct{
    int someInt, someOtherInt; // these data members are private
    pub int x; // this is public
}
```

Similarly, there is the `ipub` keyword, to only allow read-only access outside
module:

```
pub struct SomeStruct{
    int i; // private
    pub int j; // public read/write
    ipub int k; // public read only
}
```

Visibility applies at module level. Within the same module, public/private
does not matter, anything declared within a module, is accessible anywhere in
the module.

---

# If Statements

```
if CONDITION_EXPR
    STATEMENT_ON_TRUE
```

or:

```
if CONDITION_EXPR
    STATEMENT_ON_TRUE
else
    STATEMENT_ON_FALSE
```

---

# Loops

## While:

```
while CONDITION_EXPR
    STATEMENT
```

`CONDITION_EXPR` is evaluated, if `true`, STATEMENT is executed, repeat.

## Do While:

```
do 
    STATEMENT
while CONDITION_EXPR;
```

STATEMENT is executed, then `CONDITION_EXPR` is evaluated, if `true`, repeat.

## For:

For loops uses `Ranges` to iterate over members of a value.

A for loop can be written as:

```
for (counter; type value; range)
    writeln(counter + 1, "th value is ", value);
// or
for (type value; range)
    writeln(value);
```

Example:

```
var auto data = getStuff();
for (auto val; data)
    writeln(val);

// is equivalent to:
auto range = data.opRange;
while !range.isEmpty {
    var auto val = range.front;
    writeln(val);
    range.popFront;
}
```

## Ranges

A data type `T` can qualify as a range if the following operations can be
evaluated on it:

```
T.isEmpty; // should return true if there are no more values left to pop
T.front; // current value
T.popFront; // pop current element
```

To make a data type `X` iterable, `X.opRange` should return a range, for
example:

```
fn opRange(X) -> RangeObjectOfX{
    return RangeObjectOfX(X);
}
```

## Ranges Example

```
struct ArrayRange $($type T) {
    $slice(T) arr; // ref to array
    uint index;
}
fn opRange $($type T) (@const T[] arr) -> ArrayRange(T){
    return {arr = arr, index = 0}.(ArrayRange(T));
}
alias isEmpty $(alias R : ArrayRange(T), $type T) = (R.index >= R.arr.length);
alias front $(alias R : ArrayRange(T), $type T) = R.arr[R.index];
alias popFront $(alias R : ArrayRange(T), $type T) = void{ R.index ++; };
```

## Break & Continue

A `break;` statement can be used to exit a loop at any point, and a `continue;`
will jump to the end of current iteration.

---

# Switch Case

```
switch EXPRESSION
case EXPRESSION { ... }
case EXPRESSION { ... }
case _ { ... } // default
```

the switch expression is matched, whichever case expression it matches with,
that block is executed, every other case's block is skipped:

```
switch option
case "read" { line = readln; }
case "write" { line.writeln; }
case _ {}
```

A switch case is terminated by the default case, which is denoted by:

```
case _ {}
```

## Switching on Unions

The switch statement can be used on union tags. The switch expression should
evaluate to a value of union type, and case expressions should be member names:

```
var union { string s; int i; } foo = getFromSomeWhere;
switch foo
case s { foo.s.writeln; }
case i { foo.i.writeln; }
case _ {}
```

In case of unnamed unions, switching can be done on data types:

```
var union {string; int;} foo = getFromSomeWhere;
switch foo
case string { ... }
case int { ... }
```

---

# Operators

Operators are read in this order (higher precedence to lower), comma separated:

- `- A`
- `A . B`, `A -> B`
- `A [ B`
- `@ A`
- `A ( B`
- `# A` only used for attributes
- `A ?`, `A ?? B`, `A ++`, `A --`
- `A @`, `A ...`
- `~ A`, `is A`, `!is A`, `! A`
- `A * B`, `A / B`, `A % B`
- `A + B`, `A - B`
- `A << B`, `A >> B`
- `A & B`, `A | B`, `A ^ B`
- `A : B`, `A == B`, `A != B`, `A >= B`, `A <= B`, `A > B`, `A < B`, `A is B`,
    `A !is B`
- `A && B`, `A || B`
- `A = B`, `A += B`, `A -= B`, `A *= B`, `A /= B`, `A %= B`, `A &= B`,
    `A |= B`, `A ^= B`
- `A , B` (A comma B)

Some of these operators cannot be used in usual expressions:

- `# A` can only be used to tag definitions with attributes
- `A ...` can only be used on `$type` and  `alias` in defining template
    parameters

## Syntactic Sugar Operators

### Compound Assignment Operators

All variations of the assignment operator that combine an arithmetic operator
`op` with `=` to make `op=` are translated from `A op= B;` into `A = A op B;`

## Operator Overloading

Following operators can be overloaded:

- `- A`
- `A [ B`
- `A ++`
- `A --`
- `~ A`
- `! A`
- `A * B`
- `A / B`
- `A % B`
- `A + B`
- `A - B`
- `A << B`
- `A >> B`
- `A & B`
- `A | B`
- `A ^ B`
- `A == B`
- `A != B`
- `A >= B`
- `A <= B`
- `A > B`
- `A < B`

Operators are translated as:

- `a op b` Binary operator is translated to `opBin("op", a, b)`
- `op a` Unary operator is translated to `opPre("op", a)`
- `a op` Unary operator is translated to `opPost("op", a)`
- `a[x, y]` is translated to `opIndex(a, x, y)`

### Overloading using Standard Library

The standard library shall provide implementation for several operators,
indirectly allowing usage of the `opCmp` and other functions listed below, to
implement said operators.

Following operators are translated as:

- `a > b` as `opCmp(a, b) == 1`
- `a < b` as `opCmp(a, b) == -1`
- `a >= b` as `opCmp(a, b) != -1`
- `a <= b` as `opCmp(a, b) != 1`
- `a == b` as `opCmp(a, b) == 0` - read below
- `a != b` as `opCmp(a, b) != 0` - read below

The `==` and `!=` operators are first tried as:

**`a == b`**:

1. `opBin("==", a, b)`
1. `opBin("!=", a, b) == false`
2. `opCmp(a, b) == 0`

**`a != b`**:

1. `opBin("!=", a, b)`
2. `opBin("==", a, b) == false`
3. `opCmp(a, b) != 0`

In short: implementing `opCmp` will make all equality/inequality operators
possible. Implementing `opBin("==", a, b)`, or `opBin("!=", a, b)` will make
`==`, and `!=` possible. In case `opCmp` and `opBin` both are found, `==` and
`!=` will be done through `opBin` and the remaining through `opCmp`

## Example

```
struct Length{
    pub uint len;
    pub alias this = len;
    pub string unit = "cm";
}

template opBin $(string op : "+", alias a : Length, alias b : Length){
    alias this = Optional(Length){
        if (a.unit != b.unit)
            Err!; // assuming Err is a template from stdlib to create error
        return {a.len + b.len, unit = a.unit}.Length;
    };
}
```

---

# Error Handling

Alis offers some Error Handling Operators to aid in using Errors-as-Values.

## Erroneous Values

`X.isVal` is used to determine if a value is erroneous. It can be implemented
in many ways:

```
union OptionalInt{ int; struct{}; }
// as function:
fn isVal(OptionalInt o) -> $unionIs(o.int);
// as alias template
alias isVal $(alias V : OptionalVal) = $unionIs(V.int);
// or as a member:
struct OptionalIntStruct{ int val; bool isVal = false; }
```

`X.val` is used to unwrap a possible erroneous value into a value. This can be
implemented in many ways:

```
// as a function
fn val(OptionalInt o) -> o.int;
// as an alias
alias val $(alias V : OptionalInt) -> V.int;
// or simply name it in the union
union OptionalInt{
    int val;
    struct{} _;
}
```

## postfix `?` operator

The `a ?` operator checks if a value is `.isVal`, if so, it is unwrapped as
`_.val`, if not, the original unwrapped value is short-circuited upto:

- entire expression
- either side of `=`, i.e: the `=` will **not** be short circuited

```
var auto i = foo? + bar?;
```

`foo? + bar?` is evaluated as:

1. `foo` evaluated, result referred to as `V0`
2. `V0.isVal.$is(false)` ? if so, return `V0`
3. `bar` evaluated, result referred to as `V1`
4. `V1.isVal.$is(false)` ? if so, return `V1`
5. `V0.val + V1.val` evaluated and returned

Note that `V0` and `V1` identifiers are not actually created, these names are
used here only to illustrate.

The return data type of the expression `foo? + bar?` will be:

```
union {
    union {
        foo.$type; bar.$type;
    } err;
    $type(foo.val + bar.val) val;
    alias this = val;
}
```

The union is built with 2 members:

- `val` - the value in case of no error(s)
- `err` - error value(s). In case different types of errors are possible, this
    will be a union of them.

## binary `??` operator

In case LHS is erroneous, this can be used to do one of the following:

- rewrite the error before returning it
- `return`
- `break`
- `continue`

For example:

```
fn sumIntStr(string a, string b) -> (a.int? + b.int?) ?? 0;
sumIntStr("5", "6").writeln; // 11
sumIntStr("5", "six").writeln; // 0
sumIntStr("five", "6").writeln; // 0
```

The `?` operators here are used to short circuit upto the `()`, where `??`
rewrites the value to `0`.

Similarly, `??` can be used as follows as well:

- `LHS ?? return Y`
- `LHS ?? break`
- `LHS ?? continue`

In RHS of the `??` operator, the `_` identifier can be used to refer to the
erroneous value:

```
fn logAndReturn $($type T)(T val) -> T {
    val.to(string).writeln;
    return val;
}
fn toInt(string s) -> s.int ?? { isVal = false, err = _ };
```

---

# Type Casting

The compiler attempts implicit casting by rewriting expressions. To cast `x`
to type `T`, compiler will rewrite `x` to:

```
opCast(T, x)
// and if that does not compile, then:
opCast(T)(x)
```

Implicit casting is provided by default for:

- `$int(A)` to `$int(B)` where `A < B`
- `$uint(A)` to `$int(B)` where `A < B`
- `$uint(A)` to `$uint(B)` where `A < B`
- `$float(A)` to `$float(B)` where `A < B`
- `$int(A)` to `$float(B)` where `A <= B`
- `$uint(A)` to `$float(B)` where `A < B`
- `$uint(A)` to `$char` where `A == 8`
- `$int(X)` to `bool` for any `X`
- `$uint(X)` to `bool` for any `X`
- `T` to `const T` for any type `T`
- Anonymous struct `A` to struct `B` where `A` is a subset of `B`, and
    remaining elements of `B` can be auto initialized.
- Unnamed union `A` to Unnamed union `B` where `A` is a subset of `B`

Explicit casting is done as:

```
TYPE_NAME ( VALUE )
```

For example:

```
float (5) == 5.0
```

Alternatively, since `a.b` is equivalent to `b(a)`:

```
5.float == 5.0
```

---

# Conditional Compilation

## `$if`

`$if` can be used to determine which branch of code to compile:

```
$if (platformIsLinux){
    enum string PlatformName = "Linux";
}
else{
    enum string PlatformName = "Other";
}
```

## `$for`

`$for` iterates over a container that is available at compile time,
and copies its body for each element:

```
// this loop will not exist at runtime
$for (int num; [0, 5, 4, 2]){
    writeln(num.to(string));
}
```

Since a `$for` will copy it's body, it will result in redefinition
errors if any definitions are made inside. To avoid, do:

```
$for (int num; [0, 5, 4, 2]){{
    enum square = num * num;
    writeln(square.to(string));
}}
```

Since `$for` is evaluated at compile time, it can iterate over sequnces:

```
$for (int num; (0, 5, 4, 2)){
    num.to(string).writeln;
}
```

## `$switch`

Similar to the regular switch case, this one is evaluated at compile time.

---

# Templates

A template can be declared using the `template` keyword followed by name and a
sequence of template parameters:

```
// an overly complicated way to create global variables of a type
template globVar $($type T){
    var T this;
}

template square $(int x){
    enum int this = getSquare(x); // function call will be made at compile time
    fn getSquare(int x) -> x * x;
}

template sum $(T x, T y, $type T){
    enum T this = x + y;
}
```

Since the enums inside the template are named `this`, the resulting enum
will replace the template whereever initialised:

```
globVar(int) = 5;
writeln(globVar(int)); // prints 5
writeln(square(5)); // prints 25
writeln(sum(5.5, 2)); // prints 7.5
```

As shown above, templates are initialised similar to a function call

## Conditions

Templates can be tagged with an if condition block, to only initialize if
it evaluates to true. The `$(..)` template parameters can be followed by an
`if` condition

```
template foo $($type T) if (someCondition(T)){
    enum string this = "bar";
}
```

Another way to condition a template is through the `:` operator in template
paramters list:

```
template typeStr $($type T : int){
    enum string this = "int";
}
template typeStr $($type T : double){
    enum string this = "double"
}
template number $($type T : (int, double)){
    alias this = T;
}
```

The `:` operator has different behaviors, depending on how it is used:

When used as `$(TYPE NAME : EXPR)`, it will match values:

```
$(int x : 5) // template specialization, when x is an int with value 5
```

When used as `$($type NAME : EXPR)`, it will match type:

```
$($type T : int) // template specialization, when T is int
```

When used as `$(alias NAME : EXPR)`, it will match type:

```
$(alias A : SomeStruct) // template specialization, when A is an expression 
                        // whose $typeOf is SomeStruct
```

## Mixin

A template can be mixin'd; initialized in the context where it is called. This
can be done by prefixing any template definition by the `mixin` keyword:

```
template mixin xTimes $(alias F : @fn ()->void, uint times){
    $for (auto i; range(0, times)){
        F();
    }
}
fn main() -> void{
    mixin xTimes (foo, 5); // equivalent to calling foo 5 times
}
```

mixins are initialized as `mixin MIXIN_NAME (PARAM_LIST)`. The `.` operator
cannot be used in place of `()` in case of mixins.

## Functions

Function templates are defined as regular functions with an extra tuple for
template parameters:

```
fn sum $($type T) if (someCondition) (T a, T b) -> T {
    return a + b;
}
// or
fn sum $($type T) (T a, T b) -> T {
    return a + b;
}
// or
template sum $($type T) {
    fn this(T a, T b) -> T {
        return a + b;
    }
}
```

A Function Template **cannot** receive template parameters, it can only
receive function call parameters, as such, all template parameters must be
related to function parameters:

```
fn identity $($type T) (T val) -> val;

5 == 5.identity;
5 == identity(5);
```

To receive additional template parameters, which are not used in parameters:

```
template foo $(alias... S){
    fn this $($type T) (T val) -> val;
}

// Seq passed for `S`. Cannot pass T directly, inferred from 5
foo(Seq) (5); 
```

## Enums

Templates can be used to create compile time constants:

```
template TypeName $($type T){
    $if (T is int)
        enum string this = "int";
    else $if (T is double)
        enum string this = "double";
    else $if (T is string)
        enum string this = "string";
    else
        enum string this = "weird type";
}
// or
enum string TypeName $($type T) = doSomethingAtCompileTime();

fn typeIsSupported $($type T) () -> bool{
    return TypeName(T) != "weird type";
}
```

## Structs

```
struct Position $($type T) if someCondition(T) {
    T x, y;
}
// or
template Position $($type T){
    struct this{
        T x, y;
    }
}
alias PositionDiscrete = Position(int);
alias PositionContinuous = Position(float);
```

## Unions

```
union Optional $($type T) if ($isType(T)){
    pub T val;
    pub void none;
}
```

## Variables

No direct syntax is provided for templating `var` declarations, use the
following instead:

```
template foo $($type T) {
    var T this;
}
```

## Aliases

```
alias X $($type T) = T;
```

## Sequences

Sequences are compile time lists of aliases.

A sequence can be defined as: `(a, b, c)`

A template can receive a sequence as:

```
template foo $(alias... T){}
```

A sequence containing aliases to types can be used to declare a sequence of
variables:

```
fn sum $(alias... T) (T params) -> T[0]{
    var T[0] ret;
    $for (auto val; params)
        ret = ret + val;
    return ret;
}
```

Length of a sequence can be found through the `$seqLen` intrinsic:

```
fn printLength $(alias... T) () -> void{
    $seqLen(T).writeln;
}
```

Indexed access on sequences is possible through the `$seqInd` intrinsic:

```
fn sum $(alias... T) () -> void{
    for (auto i; range(0, T.$seqLen))
        T.$seqInd(i).writeln;
}
```

Sequences, when used, are expanded:

```
fn printSeq $(alias... T, int Max) () -> void{
    $for (auto i; range(0, min(Max, T.$seqLen)))
        T.$seqInd(i).to(string).writeln;
}

alias Seq = ("a", "b", 5, 10);
printSeq(Seq); // "a", "b", 5 go to T... and 10 goes to Max
```

Due to this, a template cannot receive more than one Sequence in template
parameters. Something similar can be achieved through a template of a template:

```
template Foo $(alias... A){
    template Bar $(alias... B){
    }
}
// Use like:
Foo(SeqA)(SeqB);
```

This also means that Sequences cannot be multi-dimensional.

---

# Calling Through Dot Operator

The dot operator can be used to pass parameters to callables, i.e: functions &
templates.

When resolving `a.b`, first it tries if `"b"` is a member of `a`'s type. If so,
it resolves to `$member(a, "b")`.

If `"b"` is not a member of `a`, then `a.b` translates to `b(a)`. This applies
to both cases: where `b` is a function, and where `b` is a template. This
applies to where `a` is a sequence as well:

```
(a, b).foo(c);
// is equivalent to:
foo(a, b, c);
```

---

# Intrinsics

Compiler intrinsics, written as:

```
$name(args...)
```

These will be added as the compiler and runtime is developed, since they are
directly dependent on the underlying data structures in the compiler/runtime.

## Types

- `type` - template paramater type, can accept data type
- `noinit` - a data type, of zero size, and no default value
- `noinitVal` - a value of type `$noinit`
- `init(T)` - Gets initialization value for type `T`.
- `int(X)` - data type, signed integer of X bits
- `uint(X)` - data type, unsigned integer of X bits
- `float(X)` - data type, floating point number of X bits
- `char` - data type, an 8 bit character
- `slice(X)` - data type, fixed size contiguous block, elements of type `X`
- `array(X)` - data type, contiguous block, elements of type `X`
- `isType(T)` - whether `T` resolves to a type.
- `typeOf(symbol)` - data type of a symbol

## Arrays & Sequences

- `arrLen(A)` - array length get, for array `A`
- `arrLen(A, l)` - array length set, to `l`, for array `A`
- `arrInd(A, i)` - Gets element from array, at index `i`, for array `A`
- `seqLen(T...)` - gets length of the `T...` sequence, in `uint`.
- `seqInd(T..., uint I)` - gets `I`th element in the `T...` sequence.

## Unions & Aggregates

- `unionIs(T.M)` - whether a union's tag indicates `M` member being stored, or
    member of type `M`.
- `membersCount(T)` - gets number of members in a data type `T`, which can be a
    union, struct, or enum.
- `memberNames(T, I)` - gets sequence of names of member with `memberId == I`,
    of a union, struct, or enum `T`. Multiple names per single member are
    possible due to aliases. `memberId` is the member index, which goes up to
    `membersCount(T) - 1`. Only names accesible in current scope are included.
    Note that not all members will be named. In case of `T` being an enum,
    this gets the name of a member at index `I`.
- `memberIds(T, N)` - gets sequence of `memberId` (`uint`) for sequence of
    members referred to by a `name == N`, on a union/struct type `T`. Only
    works if `N` is accessible in current scope. In case `T` is an enum, the
    result is a single `uint`, or empty sequence.
- `member(T, N)` - gets member on a union/struct instance `T`. `N` is the 
    member name (`string`).

## Attributes

- `attrsOf(X)` - gets sequence of all attributes of `X`.
- `byAttrs(X, A)` - gets sequence of all symbols, that are members of `X`,
    which are of type `A`. `X` can be a module, struct, enum, or function
    (parameters are considered members). `A` can be a type: attributes of type
    `A` will be matched. `A` can be a value: attributes of type and value of `A`
    will be matched.

# Misc.

- `debug` - whether building in debug mode or not.
- `stackTrace` - only available in `$debug`. Gives a stack trace.
- `err(str)` - Emits error as a compiler error

## Printing

These should only be used for debugging. 

- `rtWrite(T...)` - prints parameters, at runtime. **Only for debugging Alis
    itself. May not be available in final version**
- `ctWrite(T...)` - prints parameters, at compile time.

## Arithmetic Operations

Any intrinsic here that accepts 2 parameters, both should be of the same type.

- `negate(X)` - returns `X` with negated sign
- `bitNot(X)` - returns bitwise not of `X`
- `bitOr(X, Y)` - returns bitwise or of `X` and `Y`
- `bitAnd(X, Y)` - returns bitwise and of `X` and `Y`.
- `bitXor(X, Y)` - returns bitwise xor of `X` and `Y`
- `add(X, Y)` - returns `X+Y`
- `sub(X, Y)` - returns `X-Y`
- `mul(X, Y)` - returns `X*Y`
- `div(X, Y)` - returns `X/Y`
- `mod(X, Y)` - returns `X%Y`. Only for integers, not floats.

For the left/right shift, `X` and `Y` must be integers. Same type is not
required:

- `shiftL(X, Y)` - returns `X << Y`
- `shiftR(X, Y)` - returns `X >> Y`

## Comparison

- `is(X, Y)` - `true` if `X` is `Y`.
- `isNot(X, Y)` - `true` if `X` not equals `Y`.
- `isLess(X, Y)` - `true` if `X` less than `Y`.
- `not(X)` - `true` if `X` is `false`.

## Type Casting

- `to(X, T)` - casts `X` to type `T`. Works only for primitives.

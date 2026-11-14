@testitem "cluster_low_cohesion flags a file split into independent concerns" setup = [Fixtures] tags = [:cohesion] begin
    # Two groups, each sharing a helper, with no binding between them: two components.
    src = """
    ha(x) = x + 1
    a1(p) = ha(p)
    a2(p) = ha(p) + 1
    hb(y) = y * 2
    b1(q) = hb(q)
    b2(q) = hb(q) + 1
    """
    files = [Fixtures.parsedfile(:julia, src; file = "c.jl")]
    graph = Dendro.build_corpus_graph(files, Dendro.corpus_symbols(files))
    hit = only(Dendro.cluster_low_cohesion(files, graph; band = (2, 3)))
    @test hit.metric == :low_cohesion
    @test hit.kind == :scalar
    @test hit.value == 2
    @test hit.absolute == :warn
    # One representative per component, ordered by line: each group's helper.
    @test [(l.unit, l.line) for l in hit.locations] == [("ha", 1), ("hb", 4)]
end

@testitem "cluster_low_cohesion flags a split file across the language boundary" setup = [Fixtures] tags = [:cohesion] begin
    # The binding -> graph -> finding path holds beyond Julia: a python file split into
    # two concerns, each group sharing a helper, with no binding between them.
    src = """
    def ha(x):
        return x + 1
    def a1(p):
        return ha(p)
    def a2(p):
        return ha(p) + 1
    def hb(y):
        return y * 2
    def b1(q):
        return hb(q)
    def b2(q):
        return hb(q) + 1
    """
    files = [Fixtures.parsedfile(:python, src; file = "c.py")]
    graph = Dendro.build_corpus_graph(files, Dendro.corpus_symbols(files))
    hit = only(Dendro.cluster_low_cohesion(files, graph; band = (2, 3)))
    @test hit.metric == :low_cohesion
    @test hit.value == 2
    @test hit.absolute == :warn
    @test [(l.unit, l.line) for l in hit.locations] == [("ha", 1), ("hb", 7)]
end

@testitem "cluster_low_cohesion passes a cohesive file" setup = [Fixtures] tags = [:cohesion] begin
    # Every function reaches the one helper, directly or through another: one component.
    src = """
    h(x) = x + 1
    f1(p) = h(p)
    f2(p) = h(p) + h(p)
    f3(p) = h(f1(p))
    """
    files = [Fixtures.parsedfile(:julia, src; file = "c.jl")]
    graph = Dendro.build_corpus_graph(files, Dendro.corpus_symbols(files))
    @test isempty(Dendro.cluster_low_cohesion(files, graph; band = (2, 3)))
end

@testitem "cluster_low_cohesion links TypeScript methods through this" setup = [Fixtures] tags = [:cohesion] begin
    # Methods sharing a declared field, a constructor parameter property, or a call made
    # inside a callback each form one component; methods on different fields do not.
    @test Fixtures.cohesive(:typescript, "class Store {\n  private count = 0;\n  bump(): void { this.count += 1; }\n  read(): number { return this.count; }\n}\n")
    @test Fixtures.cohesive(:typescript, "class Holder {\n  constructor(private readonly items: string[]) {}\n  first(): string { return this.items[0]; }\n}\n")
    @test Fixtures.cohesive(:typescript, "class Runner {\n  start(): void { [1, 2].forEach(n => this.step(n)); }\n  step(n: number): void { }\n}\n")
    @test !Fixtures.cohesive(:typescript, "class Pair {\n  private a = 0;\n  private b = 0;\n  getA(): number { return this.a; }\n  getB(): number { return this.b; }\n}\n")
end

@testitem "cluster_low_cohesion links JavaScript methods through this" setup = [Fixtures] tags = [:cohesion] begin
    @test Fixtures.cohesive(:javascript, "class Store {\n  count = 0;\n  bump() { this.count += 1; }\n  read() { return this.count; }\n}\n")
    @test Fixtures.cohesive(:javascript, "class Runner {\n  start() { [1].forEach(n => this.step(n)); }\n  step(n) { }\n}\n")
    @test !Fixtures.cohesive(:javascript, "class Pair {\n  a = 0;\n  b = 0;\n  getA() { return this.a; }\n  getB() { return this.b; }\n}\n")
end

@testitem "cluster_low_cohesion links a callable bound to a name to its callers" setup = [Fixtures] tags = [:cohesion] begin
    # `const f = () => ...` binds the name in the declarator beside the arrow, outside the
    # callable's own span, so the definition still belongs to the unit it names.
    @test Fixtures.cohesive(:typescript, "const quoted = (t: string) => t.trim();\nexport const literal = (t: string) => quoted(t);\n")
    @test Fixtures.cohesive(:javascript, "const quoted = (t) => t.trim();\nexport const literal = (t) => quoted(t);\n")
    @test Fixtures.cohesive(:typescript, "const quoted = function (t: string) { return t; };\nexport const literal = (t: string) => quoted(t);\n")
    @test Fixtures.cohesive(:javascript, "const quoted = function (t) { return t; };\nexport const literal = (t) => quoted(t);\n")
    @test !Fixtures.cohesive(:typescript, "const quoted = (t: string) => t;\nexport const literal = (t: string) => t;\n")
end

@testitem "cluster_low_cohesion links a value's callables to the units that read its name" setup = [Fixtures] tags = [:cohesion] begin
    # `SHAPE` is no unit, so the arrows its initialiser holds and the helpers it names
    # belong to it, and through its name to the function that reads the table.
    table(typed) = """
    const isNumber = (v$(typed)) => typeof v === 'number';
    const isNames = (v$(typed)) => Array.isArray(v);
    const SHAPE = { order: isNames, sizes: (v$(typed)) => Object.values(v).every(isNumber) };
    export function check(saved$(typed)) { return Object.entries(SHAPE).every(([k, fits]) => fits(saved[k])); }
    """
    @test Fixtures.cohesive(:typescript, table(": any"))
    @test Fixtures.cohesive(:javascript, table(""))

    # A table nothing reads stays apart from the function beside it.
    unread = "const isNames = (v: any) => Array.isArray(v);\nconst SHAPE = { order: isNames };\nexport function check(saved: any) { return saved; }\n"
    @test !Fixtures.cohesive(:typescript, unread)
end

@testitem "cluster_low_cohesion links TypeScript units through a shared type" setup = [Fixtures] tags = [:cohesion] begin
    uses(type) = "export function f(r: $type) { return r.a; }\nexport function g(r: $type) { return r.a + 1; }\n"
    @test Fixtures.cohesive(:typescript, "type Row = { a: number };\n" * uses("Row"))
    @test Fixtures.cohesive(:typescript, "import type { Row } from './rows';\n" * uses("Row"))
    @test Fixtures.cohesive(:typescript, "import { type Row } from './rows';\n" * uses("Row"))
    @test Fixtures.cohesive(:typescript, "import type { Base as Row } from './rows';\n" * uses("Row"))
    @test Fixtures.cohesive(:typescript, "import type Row from './rows';\n" * uses("Row"))
    # An imported value is a shared utility, not a shared concern, so it links nothing.
    @test !Fixtures.cohesive(:typescript, "import { quoted } from './q';\nexport function f(t: string) { return quoted(t); }\nexport function g(t: string) { return quoted(t) + 1; }\n")
end

@testitem "cluster_low_cohesion links Python methods through self" setup = [Fixtures] tags = [:cohesion] begin
    # A field `__init__` assigns is declared there; a write elsewhere is a use of it.
    @test Fixtures.cohesive(:python, "class Store:\n    def __init__(self):\n        self.count = 0\n    def bump(self):\n        self.count += 1\n    def reset(self):\n        self.count = 0\n")
    @test Fixtures.cohesive(:python, "class Runner:\n    def start(self):\n        return list(map(lambda n: self.step(n), [1]))\n    def step(self, n):\n        return n\n")
    # A field binds in its own class: two classes sharing a field name stay apart.
    @test !Fixtures.cohesive(:python, "class A:\n    def __init__(self):\n        self.v = 0\n    def read(self):\n        return self.v\nclass B:\n    def __init__(self):\n        self.v = 0\n    def read(self):\n        return self.v\n")
end

@testitem "cluster_low_cohesion links Java methods through this" setup = [Fixtures] tags = [:cohesion] begin
    @test Fixtures.cohesive(:java, "class Store {\n  private int count = 0;\n  void bump() { this.count += 1; }\n  int read() { return count; }\n}\n")
    @test Fixtures.cohesive(:java, "class Runner {\n  void start() { java.util.List.of(1).forEach(n -> this.step(n)); }\n  void step(int n) { }\n}\n")
    @test !Fixtures.cohesive(:java, "class Pair {\n  private int a, b;\n  int getA() { return this.a; }\n  int getB() { return this.b; }\n}\n")
end

@testitem "cluster_low_cohesion links PHP methods through \$this" setup = [Fixtures] tags = [:cohesion] begin
    # A declared property and a promoted constructor parameter both bind in the class.
    @test Fixtures.cohesive(:php, "<?php\nclass Store {\n  private \$count = 0;\n  function bump() { \$this->count += 1; }\n  function read() { return \$this->count; }\n}\n")
    @test Fixtures.cohesive(:php, "<?php\nclass Holder {\n  function __construct(private array \$items) {}\n  function first() { return \$this->items[0]; }\n}\n")
    @test Fixtures.cohesive(:php, "<?php\nclass Runner {\n  function start() { array_map(fn(\$n) => \$this->step(\$n), [1]); }\n  function step(\$n) { }\n}\n")
    @test !Fixtures.cohesive(:php, "<?php\nclass Pair {\n  private \$a = 0;\n  private \$b = 0;\n  function getA() { return \$this->a; }\n  function getB() { return \$this->b; }\n}\n")
end

@testitem "cluster_low_cohesion links Ruby methods through instance variables and self" setup = [Fixtures] tags = [:cohesion] begin
    @test Fixtures.cohesive(:ruby, "class Store\n  def initialize\n    @count = 0\n  end\n  def bump\n    @count += 1\n  end\n  def read\n    @count\n  end\nend\n")
    @test Fixtures.cohesive(:ruby, "class Runner\n  def start\n    [1].each { |n| self.step(n) }\n  end\n  def step(n)\n    n\n  end\nend\n")
    # An instance variable binds in its own class: two classes sharing a name stay apart.
    @test !Fixtures.cohesive(:ruby, "class A\n  def initialize\n    @v = 0\n  end\n  def read\n    @v\n  end\nend\nclass B\n  def initialize\n    @v = 0\n  end\n  def read\n    @v\n  end\nend\n")
end

@testitem "cluster_low_cohesion links Rust methods through self" setup = [Fixtures] tags = [:cohesion] begin
    @test Fixtures.cohesive(:rust, "struct Store { count: i32 }\nimpl Store {\n  fn bump(&mut self) { self.count += 1; }\n  fn read(&self) -> i32 { self.count }\n}\n")
    @test Fixtures.cohesive(:rust, "struct Runner;\nimpl Runner {\n  fn start(&self) { [1].iter().for_each(|n| self.step(*n)); }\n  fn step(&self, n: i32) { }\n}\n")
    # Only a `self` access is a use: the same field read off another value links nothing.
    @test !Fixtures.cohesive(:rust, "struct Pair { a: i32 }\nimpl Pair {\n  fn get(&self) -> i32 { self.a }\n}\nfn other(p: Pair) -> i32 { p.a }\n")
end

@testitem "cluster_low_cohesion links C++ methods through this" setup = [Fixtures] tags = [:cohesion] begin
    @test Fixtures.cohesive(:cpp, "class Store {\n  int count = 0;\n  void bump() { this->count += 1; }\n  int read() { return count; }\n};\n")
    @test Fixtures.cohesive(:cpp, "class Runner {\n  void start() { auto f = [this](int n) { this->step(n); }; f(1); }\n  void step(int n) { }\n};\n")
    @test !Fixtures.cohesive(:cpp, "class Pair {\n  int* a;\n  int b;\n  int getA() { return *this->a; }\n  int getB() { return this->b; }\n};\n")
end

@testitem "cluster_low_cohesion ubiquity drop separates concerns sharing a utility" setup = [Fixtures] tags = [:cohesion] begin
    # Two concerns, but every function also reads `FOO`. Keeping that edge folds them
    # into one component; dropping `FOO` as cross-cutting restores the two concerns.
    src = """
    const FOO = 1
    ha(x) = x + FOO
    a1(p) = ha(p) + FOO
    hb(y) = y + FOO
    b1(q) = hb(q) + FOO
    """
    files = [Fixtures.parsedfile(:julia, src; file = "c.jl")]
    table = Dendro.corpus_symbols(files)
    keep = Dendro.build_corpus_graph(files, table; within_ubiquity = 1.0)
    @test isempty(Dendro.cluster_low_cohesion(files, keep; band = (2, 3)))
    drop = Dendro.build_corpus_graph(files, table; within_ubiquity = 0.5)
    hit = only(Dendro.cluster_low_cohesion(files, drop; band = (2, 3)))
    @test hit.value == 2
end

@testitem "cluster_low_cohesion respects dendro-ignore-file" setup = [Fixtures] tags = [:cohesion] begin
    src = """
    # dendro-ignore-file: low_cohesion
    ha(x) = x + 1
    a1(p) = ha(p)
    hb(y) = y * 2
    b1(q) = hb(q)
    """
    i = Fixtures.idx(:julia, src)
    directives = Dendro.suppressions(i; file = "c.jl")
    files = [Fixtures.parsedfile(:julia, src; file = "c.jl", directives = directives)]
    graph = Dendro.build_corpus_graph(files, Dendro.corpus_symbols(files))
    hit = only(Dendro.cluster_low_cohesion(files, graph; band = (2, 3)))
    @test hit.suppressed
end

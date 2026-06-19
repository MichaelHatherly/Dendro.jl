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
    hit = only(Dendro.cluster_low_cohesion(files; band = (2, 3)))
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
    hit = only(Dendro.cluster_low_cohesion(files; band = (2, 3)))
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
    @test isempty(Dendro.cluster_low_cohesion(files; band = (2, 3)))
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
    @test isempty(Dendro.cluster_low_cohesion(files; band = (2, 3), ubiquity = 1.0))
    hit = only(Dendro.cluster_low_cohesion(files; band = (2, 3), ubiquity = 0.5))
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
    hit = only(Dendro.cluster_low_cohesion(files; band = (2, 3)))
    @test hit.suppressed
end

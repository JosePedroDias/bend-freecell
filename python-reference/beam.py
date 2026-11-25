#!/usr/bin/env python3
# Beam search with safe autoplay — the reference solver's policy.

import sys

def rng(seed):
    state = seed
    while True:
        state = (214013 * state + 2531011) & 0x7FFFFFFF
        yield state >> 16

def deal(seed):
    r = rng(seed)
    cards = list(range(52))
    out = []
    left = 52
    while left:
        j = next(r) % left
        out.append(cards[j])
        cards[j] = cards[left - 1]
        left -= 1
    return out

def is_red(s):
    return s in (1, 2)

def solve(g, beam_size=256, levels=200, verbose=False):
    cols = [[] for _ in range(8)]
    for i, raw in enumerate(deal(g)):
        cols[i % 8].append((raw % 4, raw // 4))
    cells = [None] * 4
    founds = [0, 0, 0, 0]
    autos = [0]

    def can_stack(c, onto):
        return c[1] + 1 == onto[1] and is_red(c[0]) != is_red(onto[0])

    def can_found(c, founds):
        return c[1] == founds[c[0]]

    def safe_found(c, founds):
        r = c[1] + 1
        if r <= 2:
            return True
        if is_red(c[0]):
            opp = (founds[0], founds[3])
        else:
            opp = (founds[1], founds[2])
        return min(opp) >= r - 1

    def homes(c, founds):
        return can_found(c, founds) and safe_found(c, founds)

    def autoplay(state):
        cols, cells, founds = state
        while True:
            moved = False
            for ci, c in enumerate(cells):
                if c and homes(c, founds):
                    cells[ci] = None
                    founds[c[0]] += 1
                    autos[0] += 1
                    moved = True
                    break
            if moved:
                continue
            for i, col in enumerate(cols):
                if col and homes(col[-1], founds):
                    c = col.pop()
                    founds[c[0]] += 1
                    autos[0] += 1
                    moved = True
                    break
            if not moved:
                break
        return cols, cells, founds

    def won():
        return all(f == 13 for f in founds)

    def unsorted():
        total = 0
        for col in cols:
            run = 1 if col else 0
            for i in range(len(col) - 1):
                if col[i][1] + 1 == col[i + 1][1] and is_red(col[i][0]) != is_red(col[i + 1][0]):
                    run += 1
                else:
                    break
            total += len(col) - run
        return total

    def cost():
        return (52 - sum(founds)) + unsorted() + sum(1 for c in cells if c) + autos[0]

    def candidates():
        out = []
        free_cells = sum(1 for c in cells if c is None)
        capacity = free_cells + 1
        for ci, c in enumerate(cells):
            if c:
                for j, col in enumerate(cols):
                    if not col or can_stack(c, col[-1]):
                        out.append(('cx', ci, j))
        for i, col in enumerate(cols):
            if col:
                run = [col[-1]]
                while len(run) < len(col) and can_stack(run[-1], col[-len(run) - 1]):
                    run.append(col[-len(run) - 1])
                k = min(len(run), capacity)
                for j, col2 in enumerate(cols):
                    if i == j:
                        continue
                    t = col2[-1] if col2 else None
                    if t is not None and can_stack(run[k - 1], t):
                        out.append(('mv', i, j, k))
                    elif t is None and len(col) >= 1:
                        # to an empty column: not the whole sorted stack
                        # when it would just relabel the column
                        out.append(('mv', i, j, k))
        fc = next((ci for ci, c in enumerate(cells) if c is None), None)
        if fc is not None:
            for i, col in enumerate(cols):
                if col:
                    out.append(('xc', i, fc))
        return out

    def apply_mv(state, mv):
        cols, cells, founds = [c[:] for c in state[0]], list(state[1]), list(state[2])
        if mv[0] == 'cx':
            c = cells[mv[1]]; cells[mv[1]] = None; cols[mv[2]].append(c)
        elif mv[0] == 'xc':
            c = cols[mv[1]].pop(); cells[mv[2]] = c
        elif mv[0] == 'mv':
            i, j, k = mv[1], mv[2], mv[3]
            chunk = cols[i][-k:]
            del cols[i][-k:]
            cols[j].extend(chunk)
        return cols, cells, founds

    def expand_line(mv):
        # a supermove as the single moves the terminal game takes
        if mv[0] == 'mv':
            i, j, k = mv[1], mv[2], mv[3]
            free = [ci for ci, c in enumerate(cells) if c is None]
            line = []
            for t in range(k - 1):
                line.append(('xc', i, free[t]))
            line.append(('mv', i, j, 1))
            for t in range(k - 2, -1, -1):
                line.append(('cx', free[t], j))
            return line
        return [mv]

    state = autoplay((cols, cells, founds))
    beam = [(state, [], autos[0])]
    seen = set()

    def state_key(state):
        cs, ce, cf = state
        return (tuple(tuple(c) for c in cs),
                tuple(sorted(c for c in ce if c)),
                tuple(cf))

    seen.add(state_key(state))
    for level in range(levels):
        children = []
        for state, line, _ in beam:
            cols, cells, founds = state
            for mv in candidates():
                autos[0] = 0
                child = autoplay(apply_mv(state, mv))
                k = state_key(child)
                if k in seen:
                    continue
                seen.add(k)
                cline = line + expand_line(mv)
                if all(f == 13 for f in child[2]):
                    return cline, level, beam_size
                children.append((child, cline, autos[0]))
        if not children:
            break
        def real_cost(e):
            nonlocal cols, cells, founds
            cols, cells, founds = e[0]
            return (52 - sum(founds)) + unsorted() + sum(1 for c in cells if c) + e[2]
        children.sort(key=real_cost)
        beam = children[:beam_size]
        if verbose:
            best = real_cost(beam[0])
            print(f"level {level}: {len(children)} children, best cost {best}")
    return None, levels, beam_size

if __name__ == "__main__":
    g = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    verbose = len(sys.argv) > 2
    r, lv, w = solve(g, verbose=verbose)
    if r is None:
        print(f"game {g}: STUCK after {lv} levels (beam {w})")
    else:
        print(f"game {g}: WON in {len(r)} moves at level {lv}")

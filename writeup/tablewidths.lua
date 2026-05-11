-- tablewidths.lua — set per-column relative widths from cell-content length.
--
-- Pandoc's pipe-table parser leaves Table.colspecs with width = 0 (i.e. no
-- explicit width), and the LaTeX writer then asks longtable to allocate
-- equal widths per column. For tables with one wide-text column and several
-- narrow ones (e.g. Table 8: "Platform" holds long strings, "recover" /
-- "partial" hold single integers) the equal-width default reads badly.
--
-- This filter walks every Table, measures the max stringified cell length
-- per column (header included), and sets each colspec's width to a
-- fraction proportional to that max — so columns with longer text get
-- proportionally more horizontal space. The fractions are normalized to
-- 0.97 (leaving a small slack so longtable's intercolumn padding fits).

-- Inflate the apparent length of code/typewriter spans, which take ~1.3x
-- the horizontal space of proportional text per character.
local CODE_FACTOR = 1.3

local function content_weight(elt)
  local kind = elt.t or ""
  if kind == "Code" then
    return #pandoc.utils.stringify(elt) * CODE_FACTOR
  elseif kind == "Str" then
    return #elt.text
  elseif kind == "Space" or kind == "SoftBreak" then
    return 1
  elseif elt.content then
    local total = 0
    for _, sub in ipairs(elt.content) do total = total + content_weight(sub) end
    return total
  else
    return #pandoc.utils.stringify(elt)
  end
end

local function cell_len(cell)
  local total = 0
  for _, blk in ipairs(cell.contents) do
    if blk.content then
      for _, inl in ipairs(blk.content) do total = total + content_weight(inl) end
    else
      total = total + #pandoc.utils.stringify(blk)
    end
  end
  if total < 1 then total = 1 end
  return total
end

local function widen_table(tbl)
  local ncols = #tbl.colspecs
  if ncols == 0 then return tbl end
  local maxlen = {}
  for i = 1, ncols do maxlen[i] = 1 end

  local function visit_row(row)
    for i, cell in ipairs(row.cells) do
      local L = cell_len(cell)
      if L > maxlen[i] then maxlen[i] = L end
    end
  end

  for _, row in ipairs(tbl.head.rows or {}) do visit_row(row) end
  for _, body in ipairs(tbl.bodies) do
    for _, row in ipairs(body.body or {}) do visit_row(row) end
    for _, row in ipairs(body.head or {}) do visit_row(row) end
  end
  for _, row in ipairs((tbl.foot or {}).rows or {}) do visit_row(row) end

  -- Apply a soft sqrt smoothing so a single very long cell does not eat
  -- everyone else's width entirely. This keeps narrow columns above some
  -- visible minimum.
  local smoothed = {}
  local total = 0
  for i, L in ipairs(maxlen) do
    smoothed[i] = math.sqrt(L)
    total = total + smoothed[i]
  end
  if total == 0 then return tbl end

  local budget = 0.97
  for i, w in ipairs(smoothed) do
    tbl.colspecs[i][2] = (w / total) * budget
  end
  return tbl
end

return { { Table = widen_table } }

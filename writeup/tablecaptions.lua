-- tablecaptions.lua — render "**Table N.** description..." paragraphs at
-- \small (~9pt at 10pt base).
--
-- Pandoc does not emit these as LaTeX \caption{} (the user wrote them as
-- bold-prefixed paragraphs, not via pandoc's table-caption syntax), so the
-- caption package's font=small directive never reaches them. This filter
-- detects any paragraph whose first inline is a Strong span starting with
-- "Table " and wraps the whole paragraph in a \small environment when
-- writing to LaTeX/PDF.

local function is_table_caption(para)
  if not para.content or #para.content == 0 then return false end
  local first = para.content[1]
  if first.t ~= "Strong" then return false end
  local s = pandoc.utils.stringify(first)
  return s:match("^Table%s+%d") ~= nil
end

function Para(para)
  if FORMAT ~= "latex" and FORMAT ~= "beamer" then return nil end
  if not is_table_caption(para) then return nil end
  return {
    pandoc.RawBlock("latex", "\\begingroup\\footnotesize"),
    para,
    pandoc.RawBlock("latex", "\\endgroup"),
  }
end

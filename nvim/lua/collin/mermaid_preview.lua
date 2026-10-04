local M = {}

local inline_previews = {}
local browser_previews = {}
local live_server
local inline_group
local assets
local theme_override

local function remove_later(path)
  if path then
    vim.defer_fn(function()
      vim.fn.delete(path)
    end, 60000)
  end
end

local function read_file(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local contents = file:read("*a")
  file:close()
  return contents
end

local function browser_assets()
  if assets then
    return assets
  end

  local root = vim.fn.stdpath("data") .. "/lazy/markdown-preview.nvim/app/_static/"
  local mermaid = read_file(root .. "mermaid.min.js")
  local page_css = read_file(root .. "page.css")
  local markdown_css = read_file(root .. "markdown.css")
  if not mermaid or not page_css or not markdown_css then
    return nil, "Markdown Preview's bundled Mermaid.js assets are missing; install iamcco/markdown-preview.nvim"
  end

  assets = { mermaid = mermaid, page_css = page_css, markdown_css = markdown_css }
  return assets
end

local function chrome_executable()
  local candidates = {
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "google-chrome",
    "chromium",
    "chromium-browser",
  }
  for _, candidate in ipairs(candidates) do
    if vim.fn.executable(candidate) == 1 then
      return candidate
    end
  end
end

local function theme_name()
  if theme_override then
    return theme_override
  end
  local theme = vim.g.mkdp_theme
  if theme ~= "dark" and theme ~= "light" then
    theme = vim.o.background == "dark" and "dark" or "light"
  end
  return theme
end

local function mermaid_options(theme)
  local options = vim.g.mkdp_preview_options or {}
  local config = vim.tbl_extend("force", { theme = theme }, options.maid or {})
  if theme_override then
    config.theme = theme
  end
  return vim.json.encode(config)
end

local function escape_html(text)
  return text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
end

local function preview_html(source, title, interactive, raster_exports)
  local bundle, err = browser_assets()
  if not bundle then
    return nil, err
  end

  local theme = theme_name()
  local escaped_title = (title or "Mermaid diagram")
    :gsub("&", "&amp;")
    :gsub("<", "&lt;")
    :gsub(">", "&gt;")
    :gsub('"', "&quot;")
  local options = mermaid_options(theme)
  local style = {
    "html,body,#__next,main{min-height:0!important;height:auto!important;margin:0}",
    "html,body{background:" .. (theme == "dark" and "#181a1b" or "#f6f8fa") .. "}",
    "main{padding:0;background:var(--background-color)!important}",
  }
  local body, script

  if interactive then
    style[#style + 1] = table.concat({
      "#mermaid-toolbar{position:fixed;z-index:5;top:12px;left:50%;transform:translateX(-50%);display:flex;align-items:center;gap:6px;padding:8px;background:var(--background-color);border:1px solid var(--border-color);border-radius:8px;box-shadow:0 4px 20px #0005}",
      "#mermaid-toolbar button,#mermaid-toolbar select{padding:6px 10px;border:1px solid var(--border-color);border-radius:5px;background:var(--secondary-background-color);color:var(--foreground-color);font:inherit;cursor:pointer}",
      "#mermaid-toolbar button:hover{filter:brightness(1.2)}",
      "#mermaid-zoom{min-width:52px;text-align:center;font:12px ui-monospace,monospace;color:var(--foreground-color)}",
      "#mermaid-viewport{position:fixed;inset:64px 0 0;overflow:hidden;touch-action:none;cursor:grab;background:var(--background-color)}",
      "#mermaid-viewport.dragging{cursor:grabbing}",
      "#mermaid-diagram{position:absolute;left:50%;top:50%;width:max-content;height:max-content;transform-origin:center;user-select:none}",
      "#mermaid-diagram svg{display:block;max-width:none!important}",
      "#mermaid-help{position:fixed;bottom:12px;left:50%;transform:translateX(-50%);padding:6px 10px;border-radius:6px;background:var(--background-color);color:var(--foreground-color);opacity:.8;font:12px system-ui}",
      "#mermaid-help.hidden{display:none}",
    }, "\n")
    body = table.concat({
      '<body><main data-theme="' .. theme .. '">',
      '<nav id="mermaid-toolbar" aria-label="Diagram controls">',
      '<button type="button" data-action="zoom-out" aria-label="Zoom out (-)" title="Zoom out (-)">−</button>',
      '<button type="button" data-action="zoom-in" aria-label="Zoom in (+)" title="Zoom in (+)">+</button>',
      '<span id="mermaid-zoom">100%</span>',
      '<button type="button" data-action="fit" aria-label="Fit to window (f)" title="Fit to window (f)">Fit</button>',
      '<button type="button" data-action="reset" aria-label="Reset zoom (0)" title="Reset zoom (0)">100%</button>',
      '<button type="button" data-action="fullscreen" aria-label="Toggle fullscreen (F)" title="Toggle fullscreen (F)">Fullscreen</button>',
      '<button type="button" data-action="theme" aria-label="Toggle diagram light/dark theme (t)" title="Toggle diagram light/dark theme (t)">Theme</button>',
      '<select id="mermaid-export-format" aria-label="Diagram export format"><option value="svg">SVG</option><option value="png">PNG</option><option value="jpg">JPEG</option><option value="webp">WebP</option></select>',
      '<button type="button" data-action="download" aria-label="Download diagram (d)" title="Download diagram (d)">Download</button>',
      '<button type="button" data-action="help" aria-label="Toggle help (?)" title="Toggle help (?)">Help</button>',
      '</nav><div id="mermaid-viewport"><div id="mermaid-diagram" class="mermaid">',
      escape_html(source),
      '</div></div><aside id="mermaid-help">Drag to pan · Scroll to zoom · Double-click to fit · +/− zoom · h/j/k/l pan · f fit · F fullscreen · t theme · d download · raster exports use opening theme</aside>',
      '</main>',
    }, "\n")
    script = table.concat({
      "const mermaidConfig=" .. options .. ";",
      "const defaultTheme=" .. vim.json.encode(theme) .. ",requestedTheme=new URLSearchParams(location.search).get('theme');",
      "let activeTheme=requestedTheme==='dark'||requestedTheme==='light'?requestedTheme:defaultTheme;",
      "document.querySelector('main').dataset.theme=activeTheme;document.documentElement.style.background=activeTheme==='dark'?'#181a1b':'#f6f8fa';document.body.style.background=activeTheme==='dark'?'#181a1b':'#f6f8fa';mermaidConfig.theme=activeTheme;",
      "mermaidConfig.startOnLoad=false;mermaid.initialize(mermaidConfig);",
      "const viewport=document.getElementById('mermaid-viewport'),diagram=document.getElementById('mermaid-diagram'),zoomLabel=document.getElementById('mermaid-zoom'),toolbar=document.getElementById('mermaid-toolbar');",
      "const state={svg:null,width:0,height:0,zoom:1,panX:0,panY:0,drag:null,rasterExports:" .. vim.json.encode(raster_exports or {}) .. "};",
      "function draw(){if(!state.svg)return;state.svg.style.width=state.width+'px';state.svg.style.height=state.height+'px';state.svg.style.maxWidth='none';diagram.style.width=state.width+'px';diagram.style.height=state.height+'px';diagram.style.left='calc(50% + '+state.panX+'px)';diagram.style.top='calc(50% + '+state.panY+'px)';diagram.style.transform='translate(-50%,-50%) scale('+state.zoom+')';zoomLabel.textContent=Math.round(state.zoom*100)+'%';}",
      "function setZoom(value,x,y){const next=Math.max(0.08,Math.min(12,value)),ratio=next/state.zoom;if(x!==undefined){const r=viewport.getBoundingClientRect(),cx=x-r.left-r.width/2,cy=y-r.top-r.height/2;state.panX=cx-(cx-state.panX)*ratio;state.panY=cy-(cy-state.panY)*ratio;}state.zoom=next;draw();}",
      "function fit(){if(!state.width||!state.height)return;const r=viewport.getBoundingClientRect();state.zoom=Math.max(0.08,Math.min(1,(r.width-40)/state.width,(r.height-40)/state.height));state.panX=0;state.panY=0;draw();}",
      "function pan(dx,dy){state.panX+=dx;state.panY+=dy;draw();}",
      "function downloadBlob(blob,name){const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=name;document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);}",
      "function saveDiagram(format){const svg=state.svg;if(!svg)return;if(format==='svg'){const copy=svg.cloneNode(true);copy.setAttribute('width',state.width);copy.setAttribute('height',state.height);downloadBlob(new Blob([new XMLSerializer().serializeToString(copy)],{type:'image/svg+xml;charset=utf-8'}),'mermaid-diagram.svg');return;}const mime={png:'image/png',jpg:'image/jpeg',webp:'image/webp'}[format],encoded=state.rasterExports[format];if(!encoded){alert('This image export is unavailable after a live edit; SVG remains available.');return;}const a=document.createElement('a');a.href='data:'+mime+';base64,'+encoded;a.download='mermaid-diagram.'+format;document.body.appendChild(a);a.click();a.remove();}",
      "async function renderDiagram(source,preserve){diagram.textContent=source;diagram.removeAttribute('data-processed');mermaid.init(undefined,document.querySelectorAll('.mermaid'));let next;for(let i=0;i<100;i++){next=diagram.querySelector('svg');if(next?.getAttribute('viewBox'))break;await new Promise(r=>setTimeout(r,50));}state.svg=next;if(!state.svg||!state.svg.getAttribute('viewBox'))throw new Error('Mermaid.js could not render this diagram');const bounds=state.svg.getAttribute('viewBox').trim().split(/[ ,]+/).map(Number);state.width=bounds[2];state.height=bounds[3];if(!preserve){state.zoom=1;state.panX=0;state.panY=0;}draw();}",
      "toolbar.addEventListener('click',e=>{const action=e.target.closest('button')?.dataset.action;if(action==='zoom-in')setZoom(state.zoom*1.25);else if(action==='zoom-out')setZoom(state.zoom/1.25);else if(action==='fit')fit();else if(action==='reset'){state.zoom=1;state.panX=0;state.panY=0;draw();}else if(action==='fullscreen'){if(document.fullscreenElement)document.exitFullscreen();else document.documentElement.requestFullscreen?.();}else if(action==='theme'){const url=new URL(location.href);url.searchParams.set('theme',activeTheme==='dark'?'light':'dark');location.href=url.href;}else if(action==='download')saveDiagram(document.getElementById('mermaid-export-format').value);else if(action==='help')document.getElementById('mermaid-help').classList.toggle('hidden');});",
      "let drag=null;viewport.addEventListener('wheel',e=>{e.preventDefault();setZoom(state.zoom*(e.deltaY<0?1.12:1/1.12),e.clientX,e.clientY);},{passive:false});",
      "viewport.addEventListener('pointerdown',e=>{if(e.target.closest('button'))return;drag={x:e.clientX,y:e.clientY,panX:state.panX,panY:state.panY};viewport.setPointerCapture(e.pointerId);viewport.classList.add('dragging');});",
      "viewport.addEventListener('pointermove',e=>{if(!drag)return;state.panX=drag.panX+e.clientX-drag.x;state.panY=drag.panY+e.clientY-drag.y;draw();});",
      "viewport.addEventListener('pointerup',()=>{drag=null;viewport.classList.remove('dragging');});viewport.addEventListener('pointercancel',()=>{drag=null;viewport.classList.remove('dragging');});viewport.addEventListener('dblclick',e=>{e.preventDefault();fit();});",
      "window.addEventListener('resize',fit);document.addEventListener('fullscreenchange',fit);",
      "document.addEventListener('keydown',e=>{if(e.target.closest('button,input,textarea'))return;if(e.key==='+'||e.key==='=')setZoom(state.zoom*1.25);else if(e.key==='-')setZoom(state.zoom/1.25);else if(e.key==='0'){state.zoom=1;state.panX=0;state.panY=0;draw();}else if(e.key==='f')fit();else if(e.key==='F'){if(document.fullscreenElement)document.exitFullscreen();else document.documentElement.requestFullscreen?.();}else if(e.key==='t'){const url=new URL(location.href);url.searchParams.set('theme',activeTheme==='dark'?'light':'dark');location.href=url.href;}else if(e.key==='d')saveDiagram(document.getElementById('mermaid-export-format').value);else if(e.key==='h')pan(40,0);else if(e.key==='l')pan(-40,0);else if(e.key==='j')pan(0,-40);else if(e.key==='k')pan(0,40);else if(e.key==='?')document.getElementById('mermaid-help').classList.toggle('hidden');});",
      "for(const option of document.querySelectorAll('#mermaid-export-format option'))if(option.value!=='svg'&&(!state.rasterExports[option.value]||activeTheme!==defaultTheme))option.disabled=true;",
      "async function checkLiveUpdate(){try{const version=await fetch(location.pathname+'.version?'+Date.now(),{cache:'no-store'}).then(r=>r.text());if(!window.mermaidLiveVersion){window.mermaidLiveVersion=version;return;}if(version!==window.mermaidLiveVersion){const page=await fetch(location.pathname+'?'+Date.now(),{cache:'no-store'}).then(r=>r.text()),next=new DOMParser().parseFromString(page,'text/html').querySelector('#mermaid-diagram')?.textContent;if(next!==undefined){window.mermaidLiveVersion=version;state.rasterExports={};for(const option of document.querySelectorAll('#mermaid-export-format option'))if(option.value!=='svg')option.disabled=true;await renderDiagram(next,true);}}}catch(_){}}",
      "(async()=>{try{await renderDiagram(diagram.textContent,false);}catch(e){console.error(e);}checkLiveUpdate();setInterval(checkLiveUpdate,500);})();",
    }, "\n")
  else
    style[#style + 1] = ".markdown-body{background:var(--background-color)!important}#page-ctn{max-width:900px}.mermaid{margin:0!important}"
    body = table.concat({
      '<body><main data-theme="' .. theme .. '"><div id="page-ctn"><article class="markdown-body"><div class="mermaid">',
      escape_html(source),
      "</div></article></div></main>",
    }, "\n")
    script = table.concat({
      "mermaid.initialize(" .. options .. ");",
      "mermaid.init(undefined,document.querySelectorAll('.mermaid'));",
      "function sizeMermaid(){",
      "const svg=document.querySelector('.mermaid svg');",
      "if(!svg||!svg.getAttribute('viewBox')){setTimeout(sizeMermaid,50);return;}",
      "const n=svg.getAttribute('viewBox').trim().split(/[ ,]+/).map(Number);",
      "const maxWidth=svg.parentElement.getBoundingClientRect().width;",
      "const width=Math.min(n[2],maxWidth),diagramHeight=n[3]*width/n[2];",
      "svg.style.width=width+'px';svg.style.height=diagramHeight+'px';svg.style.maxWidth=width+'px';",
      "const p=document.getElementById('page-ctn').getBoundingClientRect();",
      "document.documentElement.setAttribute('data-capture-width',Math.ceil(p.width+16));",
      "document.documentElement.setAttribute('data-capture-height',Math.ceil(Math.max(p.height,diagramHeight+96)+16));",
      "}",
      "setTimeout(sizeMermaid,50);",
    }, "\n")
  end

  local markup = table.concat({
    "<!doctype html>",
    '<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">',
    "<title>" .. escaped_title .. "</title>",
    "<style>" .. bundle.page_css .. "\n" .. bundle.markdown_css .. "\n" .. table.concat(style, "\n"),
    "</style><script defer>" .. bundle.mermaid:gsub("</script", "<\\/script") .. "</script></head>",
    body,
    "<script defer>" .. script .. "</script></body></html>",
  }, "\n")

  return markup, theme
end

local function make_temp_path(suffix)
  return vim.fn.tempname() .. suffix
end

local function cleanup_preview(images, paths)
  for _, image in ipairs(images or {}) do
    pcall(function()
      image:clear()
    end)
  end
  for _, path in ipairs(paths or {}) do
    vim.fn.delete(path)
  end
end

local function clear_inline_images(entry)
  cleanup_preview(entry.images, entry.paths)
  entry.images = {}
  entry.paths = {}
  entry.signature = nil
end

local function find_mermaid_blocks(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local name = vim.api.nvim_buf_get_name(buf)
  local filetype = vim.bo[buf].filetype

  if filetype == "mermaid" or name:match("%.mmd$") then
    if #lines == 0 or (#lines == 1 and lines[1] == "") then
      return {}
    end
    return {
      {
        source = vim.trim(table.concat(lines, "\n")),
        start_row = 0,
        end_row = math.max(0, #lines - 1),
      },
    }
  end

  local blocks = {}
  local row = 1
  while row <= #lines do
    local marker, info = lines[row]:match("^%s*(```+)%s*(.-)%s*$")
    if not marker then
      marker, info = lines[row]:match("^%s*(~~~+)%s*(.-)%s*$")
    end

    local language = info and info:lower() or ""
    local is_mermaid = language == "mermaid" or language:match("^mermaid%s") or language:match("^mermaid{")
    if is_mermaid then
      local close_row = row + 1
      while close_row <= #lines do
        local close = lines[close_row]:match("^%s*(```+)%s*$")
          or lines[close_row]:match("^%s*(~~~+)%s*$")
        if close and close:sub(1, 1) == marker:sub(1, 1) and #close >= #marker then
          break
        end
        close_row = close_row + 1
      end

      if close_row > #lines then
        return blocks, "Mermaid code fence is missing its closing fence"
      end

      local source = {}
      for i = row + 1, close_row - 1 do
        source[#source + 1] = lines[i]
      end
      blocks[#blocks + 1] = {
        source = vim.trim(table.concat(source, "\n")),
        start_row = row - 1,
        end_row = close_row - 1,
      }
      row = close_row + 1
    else
      row = row + 1
    end
  end

  return blocks
end

local function source_at_cursor(buf)
  if vim.bo[buf].filetype == "mermaid" or vim.api.nvim_buf_get_name(buf):match("%.mmd$") then
    local blocks = find_mermaid_blocks(buf)
    return blocks[1] and blocks[1].source or nil, blocks[1] and 1 or nil
  end

  local cursor_row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local blocks, err = find_mermaid_blocks(buf)
  for index, block in ipairs(blocks) do
    if cursor_row >= block.start_row and cursor_row <= block.end_row then
      return block.source, index
    end
  end
  return nil, err or "Place the cursor inside a fenced Mermaid block first"
end

local function browser_html_path(buf)
  local cache_dir = vim.fn.stdpath("cache") .. "/mermaid-browser"
  vim.fn.mkdir(cache_dir, "p")
  local source_name = vim.api.nvim_buf_get_name(buf)
  return cache_dir .. "/" .. vim.fn.sha256(source_name .. tostring(buf)):sub(1, 16) .. ".html"
end

local function ensure_live_server()
  if live_server then
    return live_server
  end

  local python = vim.fn.exepath("python3")
  if python == "" then
    return nil
  end

  local socket = vim.uv.new_tcp()
  if not socket then
    return nil
  end
  local ok = socket:bind("127.0.0.1", 0)
  if not ok then
    socket:close()
    return nil
  end
  local port = socket:getsockname().port
  socket:close()

  local cache_dir = vim.fn.stdpath("cache") .. "/mermaid-browser"
  local process = vim.system(
    { python, "-m", "http.server", tostring(port), "--bind", "127.0.0.1" },
    { cwd = cache_dir, detach = true, stdout = false, stderr = false }
  )
  live_server = { port = port, process = process }
  return live_server
end

local function write_browser_html(html, path)
  local temporary_path = path .. ".tmp"
  vim.fn.writefile(vim.split(html, "\n", { plain = true }), temporary_path)
  if vim.fn.rename(temporary_path, path) ~= 0 then
    vim.fn.delete(temporary_path)
    return false
  end

  local version_path = path .. ".version"
  local version_tmp = version_path .. ".tmp"
  vim.fn.writefile({ vim.fn.sha256(html) }, version_tmp)
  if vim.fn.rename(version_tmp, version_path) ~= 0 then
    vim.fn.delete(version_tmp)
  end
  return true
end

local function open_html_in_browser(html, title, buf, block_index)
  local path = browser_html_path(buf)
  write_browser_html(html, path)
  browser_previews[buf] = { path = path, block_index = block_index, refresh = 0 }

  local server = ensure_live_server()
  local target = vim.uri_from_fname(path)
  if server then
    target = string.format("http://127.0.0.1:%d/%s", server.port, vim.fn.fnamemodify(path, ":t"))
  end
  local ok, command, err = pcall(vim.ui.open, target)
  if not ok then
    vim.notify("Could not open Mermaid preview in a browser: " .. tostring(command), vim.log.levels.ERROR)
  elseif not command then
    vim.notify("Could not open Mermaid preview in a browser: " .. tostring(err), vim.log.levels.ERROR)
  end
end

local render_block_image

local function render_mermaid_in_browser(buf)
  local source, block_index = source_at_cursor(buf)
  if not source then
    vim.notify(block_index, vim.log.levels.WARN, { title = "Mermaid browser preview" })
    return
  end

  local name = vim.api.nvim_buf_get_name(buf)
  local chrome = chrome_executable()
  if not chrome then
    local html, html_err = preview_html(source, vim.fn.fnamemodify(name, ":t"), true, {})
    if not html then
      vim.notify(html_err, vim.log.levels.ERROR, { title = "Mermaid browser preview" })
      return
    end
    vim.notify("Chrome/Chromium is unavailable; browser export is limited to SVG", vim.log.levels.WARN)
    open_html_in_browser(html, name, buf, block_index)
    return
  end

  render_block_image(chrome, source, name, function(png_path, html_path, render_err)
    remove_later(html_path)
    if not png_path then
      vim.notify("Raster exports could not be prepared: " .. tostring(render_err), vim.log.levels.WARN)
      local html, html_err = preview_html(source, vim.fn.fnamemodify(name, ":t"), true, {})
      if html then
        open_html_in_browser(html, name, buf, block_index)
      else
        vim.notify(html_err, vim.log.levels.ERROR, { title = "Mermaid browser preview" })
      end
      return
    end

    local png = read_file(png_path)
    local exports = { png = png and vim.base64.encode(png) or nil }
    local jpg_path, webp_path = make_temp_path(".jpg"), make_temp_path(".webp")
    local pending = 2
    local function finish_export(format, path, result)
      vim.schedule(function()
        if result.code == 0 then
          local bytes = read_file(path)
          if bytes then
            exports[format] = vim.base64.encode(bytes)
          end
        else
          vim.notify("Could not prepare Mermaid " .. format:upper() .. " export", vim.log.levels.WARN)
        end
        remove_later(path)
        pending = pending - 1
        if pending == 0 then
          remove_later(png_path)
          local html, html_err = preview_html(source, vim.fn.fnamemodify(name, ":t"), true, exports)
          if not html then
            vim.notify(html_err, vim.log.levels.ERROR, { title = "Mermaid browser preview" })
            return
          end
          open_html_in_browser(html, name, buf, block_index)
        end
      end)
    end

    if vim.fn.executable("magick") ~= 1 then
      exports.jpg, exports.webp = nil, nil
      pending = 0
      remove_later(png_path)
      vim.notify("ImageMagick is unavailable; SVG and PNG exports remain available", vim.log.levels.WARN)
      local html, html_err = preview_html(source, vim.fn.fnamemodify(name, ":t"), true, {})
      if html then
        open_html_in_browser(html, name, buf, block_index)
      else
        vim.notify(html_err, vim.log.levels.ERROR, { title = "Mermaid browser preview" })
      end
      return
    end

    vim.system({ "magick", png_path, "-quality", "92", jpg_path }, { text = true }, function(result)
      finish_export("jpg", jpg_path, result)
    end)
    vim.system({ "magick", png_path, "-quality", "92", webp_path }, { text = true }, function(result)
      finish_export("webp", webp_path, result)
    end)
  end)
end

local function refresh_browser_preview(buf, session)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local blocks = find_mermaid_blocks(buf)
  local block = blocks[session.block_index]
  if not block then
    return
  end

  local name = vim.api.nvim_buf_get_name(buf)
  local html, err = preview_html(block.source, vim.fn.fnamemodify(name, ":t"), true, {})
  if not html then
    vim.notify(err, vim.log.levels.WARN, { title = "Mermaid browser preview" })
    return
  end
  write_browser_html(html, session.path)
end

local function schedule_browser_refresh(buf)
  local session = browser_previews[buf]
  if not session then
    return
  end

  session.refresh = session.refresh + 1
  local refresh = session.refresh
  vim.defer_fn(function()
    if browser_previews[buf] ~= session or session.refresh ~= refresh then
      return
    end
    refresh_browser_preview(buf, session)
  end, 150)
end

local function image_signature(blocks, width, theme)
  local parts = { tostring(width), theme }
  for _, block in ipairs(blocks) do
    parts[#parts + 1] = block.source
    parts[#parts + 1] = "\0"
  end
  return vim.fn.sha256(table.concat(parts, "\n"))
end

local function capture_dimensions(dom)
  if not dom:match('<svg[^>]-viewBox="') then
    return nil
  end
  local width = tonumber(dom:match('data%-capture%-width="(%d+)"'))
  local height = tonumber(dom:match('data%-capture%-height="(%d+)"'))
  if not width or not height then
    return nil
  end
  return math.max(200, math.min(width, 3000)), math.max(160, math.min(height, 5000))
end

local function capture_args(chrome, width, height, html_path)
  return {
    chrome,
    "--headless",
    "--no-sandbox",
    "--disable-gpu",
    "--disable-dev-shm-usage",
    "--hide-scrollbars",
    "--allow-file-access-from-files",
    "--window-size=" .. width .. "," .. height,
    "--virtual-time-budget=2000",
    html_path,
  }
end

render_block_image = function(chrome, source, name, callback)
  local html, err = preview_html(source, name)
  if not html then
    callback(nil, nil, err)
    return
  end

  local html_path = make_temp_path(".html")
  local png_path = make_temp_path(".png")
  vim.fn.writefile(vim.split(html, "\n", { plain = true }), html_path)

  local inspect_args = capture_args(chrome, 1200, 1200, html_path)
  table.insert(inspect_args, #inspect_args, "--dump-dom")
  vim.system(inspect_args, { text = true }, function(inspect_result)
    vim.schedule(function()
      if inspect_result.code ~= 0 then
        callback(nil, nil, vim.trim(inspect_result.stderr or "Chrome could not render Mermaid"))
        remove_later(html_path)
        return
      end

      local width, height = capture_dimensions(inspect_result.stdout or "")
      if not width then
        callback(nil, nil, "Mermaid.js did not produce an SVG diagram")
        remove_later(html_path)
        return
      end

      local screenshot_args = capture_args(chrome, width, height, html_path)
      table.insert(screenshot_args, #screenshot_args, "--screenshot=" .. png_path)
      vim.system(screenshot_args, { text = true }, function(screenshot_result)
        vim.schedule(function()
          if screenshot_result.code ~= 0 or vim.fn.filereadable(png_path) ~= 1 then
            callback(nil, nil, vim.trim(screenshot_result.stderr or "Chrome did not save the Mermaid image"))
            remove_later(html_path)
            remove_later(png_path)
            return
          end
          vim.fn.delete(html_path)
          callback(png_path, nil)
        end)
      end)
    end)
  end)
end

local function render_inline_buffer(buf, request)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local filetype = vim.bo[buf].filetype
  if filetype ~= "markdown" and filetype ~= "rmd" and filetype ~= "mermaid" then
    return
  end

  local entry = inline_previews[buf]
  if not entry or entry.request ~= request then
    return
  end
  local blocks = find_mermaid_blocks(buf)
  if #blocks == 0 then
    clear_inline_images(entry)
    return
  end

  local win = vim.fn.bufwinid(buf)
  if win == -1 or not vim.api.nvim_win_is_valid(win) then
    return
  end
  local width = math.max(40, math.min(vim.api.nvim_win_get_width(win) - 4, 120))
  local theme = theme_name()
  local signature = image_signature(blocks, width, theme)
  if entry.signature == signature then
    for _, image in ipairs(entry.images) do
      image.window = win
      if not image.is_rendered then
        local ok, render_err = pcall(function()
          image:render()
        end)
        if not ok then
          vim.notify("Could not restore Mermaid preview: " .. tostring(render_err), vim.log.levels.WARN)
        end
      end
    end
    return
  end

  local chrome = chrome_executable()
  if not chrome then
    vim.notify("Chrome/Chromium is required to render browser-matched Mermaid previews", vim.log.levels.ERROR)
    return
  end
  local ok, image_api = pcall(require, "image")
  if not ok then
    return
  end

  local pending = { images = {}, paths = {} }
  local remaining = #blocks
  local failed = false
  local function complete_block(block, path, html_path, render_error)
    if entry.request ~= request or inline_previews[buf] ~= entry or not vim.api.nvim_buf_is_valid(buf) then
      remove_later(path)
      remove_later(html_path)
      cleanup_preview(pending.images, pending.paths)
      return
    end

    if render_error then
      failed = true
      vim.notify(render_error, vim.log.levels.WARN, { title = "Mermaid inline preview" })
    elseif path then
      local current_win = vim.fn.bufwinid(buf)
      if current_win == -1 or not vim.api.nvim_win_is_valid(current_win) then
        remove_later(path)
        remove_later(html_path)
        failed = true
      else
        local image = image_api.from_file(path, {
          window = current_win,
          buffer = buf,
          x = 0,
          y = block.end_row,
          width = width,
          max_width_window_percentage = 95,
          max_height_window_percentage = 45,
          render_offset_top = 1,
          with_virtual_padding = true,
        })
        if image then
          pending.images[#pending.images + 1] = image
          pending.paths[#pending.paths + 1] = path
          remove_later(html_path)
        else
          failed = true
          remove_later(path)
          remove_later(html_path)
        end
      end
    end

    remaining = remaining - 1
    if remaining > 0 then
      return
    end
    if failed or entry.request ~= request or inline_previews[buf] ~= entry then
      cleanup_preview(pending.images, pending.paths)
      return
    end

    for _, image in ipairs(pending.images) do
      local render_ok, render_err = pcall(function()
        image:render()
      end)
      if not render_ok then
        vim.notify("Could not display Mermaid preview: " .. tostring(render_err), vim.log.levels.WARN)
        cleanup_preview(pending.images, pending.paths)
        return
      end
    end

    local old_images, old_paths = entry.images, entry.paths
    entry.images, entry.paths = pending.images, pending.paths
    entry.signature = signature
    cleanup_preview(old_images, old_paths)
  end

  for _, block in ipairs(blocks) do
    render_block_image(chrome, block.source, vim.api.nvim_buf_get_name(buf), function(path, html_path, render_err)
      complete_block(block, path, html_path, render_err)
    end)
  end
end

local function schedule_inline_refresh(buf, delay_ms)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local entry = inline_previews[buf] or { request = 0, images = {}, paths = {} }
  inline_previews[buf] = entry
  entry.request = entry.request + 1
  entry.timer = (entry.timer or 0) + 1
  local timer, request = entry.timer, entry.request
  vim.defer_fn(function()
    if inline_previews[buf] == entry and entry.timer == timer then
      render_inline_buffer(buf, request)
    end
  end, delay_ms == nil and 700 or delay_ms)
end

function M.toggle_theme()
  theme_override = theme_name() == "dark" and "light" or "dark"
  local refreshed = false
  for buf in pairs(inline_previews) do
    if vim.api.nvim_buf_is_valid(buf) then
      schedule_inline_refresh(buf)
      refreshed = true
    end
  end
  if not refreshed then
    schedule_inline_refresh(vim.api.nvim_get_current_buf())
  end
  for buf in pairs(browser_previews) do
    if vim.api.nvim_buf_is_valid(buf) then
      schedule_browser_refresh(buf)
    end
  end
  vim.notify("Mermaid preview theme: " .. theme_override, vim.log.levels.INFO)
end

function M.browser_preview()
  local buf = vim.api.nvim_get_current_buf()
  local filetype = vim.bo[buf].filetype
  if filetype == "markdown" or filetype == "rmd" or filetype == "mermaid"
    or vim.api.nvim_buf_get_name(buf):match("%.mmd$") then
    render_mermaid_in_browser(buf)
  else
    vim.notify("The browser diagram viewer supports Markdown Mermaid fences and standalone .mmd files", vim.log.levels.WARN)
  end
end

function M.refresh()
  schedule_inline_refresh(vim.api.nvim_get_current_buf())
end

function M.setup()
  if M.commands_registered then
    return
  end
  M.commands_registered = true

  vim.api.nvim_create_user_command("MermaidBrowserPreview", M.browser_preview, {
    desc = "Open the current Mermaid diagram in an interactive browser viewer",
  })
  vim.api.nvim_create_user_command("MermaidRefresh", M.refresh, { desc = "Refresh inline Mermaid images" })
  vim.api.nvim_create_user_command("MermaidThemeToggle", M.toggle_theme, { desc = "Toggle Mermaid preview light/dark theme" })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("collin-mermaid-live-server", { clear = true }),
    callback = function()
      if live_server and live_server.process then
        pcall(function()
          live_server.process:kill(15)
        end)
      end
      live_server = nil
    end,
  })

  local function attach_preview_mappings(buf, description)
    vim.keymap.set("n", "<leader>mv", M.browser_preview, {
      buffer = buf,
      desc = description,
    })
    vim.keymap.set("n", "<leader>mD", M.toggle_theme, {
      buffer = buf,
      desc = "Toggle Mermaid preview light/dark theme",
    })
  end

  vim.api.nvim_create_autocmd("FileType", {
    pattern = "mermaid",
    group = vim.api.nvim_create_augroup("collin-mermaid-filetype-mappings", { clear = true }),
    callback = function(args)
      attach_preview_mappings(args.buf, "Browser preview of Mermaid diagram")
    end,
  })
  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "markdown", "rmd" },
    group = vim.api.nvim_create_augroup("collin-markdown-mermaid-mappings", { clear = true }),
    callback = function(args)
      attach_preview_mappings(args.buf, "Interactive Mermaid browser viewer")
    end,
  })

  inline_group = vim.api.nvim_create_augroup("collin-mermaid-inline-preview", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "TextChanged", "TextChangedI", "BufWritePost", "VimResized" }, {
    group = inline_group,
    callback = function(args)
      local buf = args.buf
      if not buf or buf == 0 then
        buf = vim.api.nvim_get_current_buf()
      end
      local delay_ms
      if args.event == "BufEnter" or args.event == "BufWinEnter" then
        delay_ms = 0
      end
      schedule_inline_refresh(buf, delay_ms)
      schedule_browser_refresh(buf)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = inline_group,
    callback = function(args)
      local entry = inline_previews[args.buf]
      if entry then
        entry.request = entry.request + 1
        clear_inline_images(entry)
        inline_previews[args.buf] = nil
      end
      browser_previews[args.buf] = nil
    end,
  })
end

return M

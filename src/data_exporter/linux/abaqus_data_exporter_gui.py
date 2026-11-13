#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Linux GUI for ODB2VTU-S Exporter.
GUI runs with system Python 3 + Tkinter.
ODB backends run with: <abaqus command> python backend.py ...
Target: Abaqus 2024/Linux (Python 3 odbAccess).
"""
import json
import os
import shlex
import subprocess
import sys
import threading
import queue
from pathlib import Path
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from tkinter import font as tkfont
from ui_i18n import translate

APP_DIR = Path(__file__).resolve().parent
META_PY = APP_DIR / 'odb_metadata.py'
FIELDS_PY = APP_DIR / 'odb_list_fields.py'
EXPORT_PY = APP_DIR / 'odb_export_vtu.py'
SERIES_PY = APP_DIR / 'odb_export_series.py'
CURVE_META_PY = APP_DIR / 'odb_curve_history_meta.py'
CURVE_EXPORT_PY = APP_DIR / 'odb_curve_history_export.py'
ANALYSIS_PY = APP_DIR / 'odb_field_analysis.py'
CPFEM_MASTER_PY = APP_DIR / 'abaqus_postprocess_master.py'
AUDIT_PY = APP_DIR / 'diagnose_output_readonly.py'
RECOVERY_PY = APP_DIR / 'odb_recovery_safe.py'
LEGACY_PY = APP_DIR / 'odb_legacy_migration.py'
def _runtime_dir():
    # Transient GUI state (metadata.json, fields.json, selected states, audit
    # report) must not live inside the program directory: a shared or read-only
    # installation path cannot be written. Prefer the per-user cache directory
    # and fall back to the program directory only when nothing else is writable.
    base = os.environ.get('XDG_CACHE_HOME') or os.path.join(os.path.expanduser('~'), '.cache')
    cand = Path(base) / 'odb2vtu-s'
    try:
        cand.mkdir(parents=True, exist_ok=True)
        probe = cand / '.write_probe'
        probe.write_text('ok')
        probe.unlink()
        return cand
    except Exception:
        fallback = APP_DIR / '.ade_runtime'
        fallback.mkdir(exist_ok=True)
        return fallback


WORK_DIR = _runtime_dir()
META_JSON = WORK_DIR / 'metadata.json'
FIELDS_JSON = WORK_DIR / 'fields.json'
CURVE_META_JSON = WORK_DIR / 'curve_metadata.json'
SERIES_FILE = WORK_DIR / 'selected_states.txt'
CURVE_STEPS_FILE = WORK_DIR / 'curve_steps.txt'

ALL_GRAINS = '<所有晶粒 / All Grains>'
WHOLE = '<整个实例 / Whole Instance>'
COF = 'COF=|RF1|/|CF2|'

# ---------------------------------------------------------------------------
# Flat desktop theme. Tk 8.5 compatible: no rounded corners, no letter-spacing,
# no PNG assets; icons are drawn on small canvases.
# ---------------------------------------------------------------------------
BG = '#FFFFFF'
SIDEBAR_BG = '#F7F7F8'
SIDEBAR_HOVER = '#EFEFF2'
BORDER = '#E4E5E9'
TEXT = '#14161A'
MUTED = '#6B7280'
FAINT = '#9AA0A8'
ACCENT = '#0F6B5C'
ACCENT_HOVER = '#0B5749'
ACCENT_SUBTLE = '#E8F1EF'
DANGER = '#B3261E'
DANGER_SUBTLE = '#FBEAE8'

_FONT_REFS = []
_UI_FAMILIES = ('Microsoft YaHei UI', 'Segoe UI', 'Noto Sans CJK SC',
                'Source Han Sans SC', 'WenQuanYi Micro Hei', 'DejaVu Sans',
                'Liberation Sans', 'Helvetica')
_MONO_FAMILIES = ('Cascadia Mono', 'Consolas', 'DejaVu Sans Mono',
                  'Liberation Mono', 'Noto Sans Mono CJK SC', 'Courier New')


def auto_wrap(label, margin=0, minimum=160):
    """Keep a hint label wrapped to the current width of its container."""
    parent = label.master

    def _apply(_event=None):
        width = parent.winfo_width() - margin
        if width >= minimum:
            label.configure(wraplength=width)

    parent.bind('<Configure>', _apply, add='+')
    label.after_idle(_apply)
    return label


def _pick_family(root, candidates):
    try:
        available = set(tkfont.families(root))
    except Exception:
        available = set()
    for name in candidates:
        if name in available:
            return name
    try:
        return tkfont.nametofont('TkDefaultFont', root=root).actual('family')
    except Exception:
        return 'DejaVu Sans'


def init_theme_fonts(root):
    """Create named fonts once and align the Tk defaults with them."""
    ui = _pick_family(root, _UI_FAMILIES)
    mono = _pick_family(root, _MONO_FAMILIES)
    specs = (
        ('AppFont', ui, 10, 'normal'),
        ('AppFontBold', ui, 10, 'bold'),
        ('AppSmall', ui, 9, 'normal'),
        ('AppSmallBold', ui, 9, 'bold'),
        ('AppTiny', ui, 8, 'normal'),
        ('AppMark', ui, 13, 'bold'),
        ('AppTitle', ui, 17, 'bold'),
        ('AppSubtitle', ui, 10, 'normal'),
        ('AppSection', ui, 11, 'bold'),
        ('AppNav', ui, 10, 'normal'),
        ('AppNavActive', ui, 10, 'bold'),
        ('AppTag', ui, 8, 'bold'),
        ('AppMono', mono, 9, 'normal'),
    )
    for name, family, size, weight in specs:
        try:
            font = tkfont.Font(root=root, name=name, exists=True)
        except Exception:
            font = tkfont.Font(root=root, name=name, exists=False)
        font.configure(family=family, size=size, weight=weight)
        _FONT_REFS.append(font)
    for name in ('TkDefaultFont', 'TkTextFont', 'TkMenuFont', 'TkTooltipFont',
                 'TkIconFont', 'TkSmallCaptionFont'):
        try:
            tkfont.nametofont(name, root=root).configure(family=ui, size=10)
        except Exception:
            pass
    for name in ('TkHeadingFont', 'TkCaptionFont'):
        try:
            tkfont.nametofont(name, root=root).configure(family=ui, size=10,
                                                         weight='bold')
        except Exception:
            pass


class Section(ttk.Frame):
    """Titled form block: bold title, hairline rule, then the form rows.

    Drop-in replacement for ttk.LabelFrame. Children are packed into this
    frame directly, exactly like the previous LabelFrame call sites.
    """

    def __init__(self, master=None, text='', padding=0, **kwargs):
        ttk.Frame.__init__(self, master, style='Section.TFrame',
                           padding=padding, **kwargs)
        self.title_label = tk.Label(self, text=text, bg=BG, fg=TEXT,
                                    font='AppSection', anchor='w')
        self.title_label.pack(fill='x')
        tk.Frame(self, bg=BORDER, height=1).pack(fill='x', pady=(6, 9))


class Check(tk.Frame):
    """Flat checkbox that matches the theme on Tk 8.5/8.6.

    ttk/clam renders its checkbox indicator from fixed images which look like a
    stray cross on both CentOS 7 and Windows, so the box is drawn on a canvas.
    """

    def __init__(self, master=None, text='', variable=None, command=None,
                 state='normal', **kwargs):
        tk.Frame.__init__(self, master, bg=BG, **kwargs)
        self.variable = variable if variable is not None else tk.BooleanVar(master=self)
        self.command = command
        self._state = state
        self._hovering = False
        self._box = tk.Canvas(self, width=15, height=15, bg=BG,
                              highlightthickness=0, cursor='hand2')
        self._box.pack(side='left')
        self._label = tk.Label(self, text=text, bg=BG, fg=TEXT, font='AppFont',
                               anchor='w', cursor='hand2')
        self._label.pack(side='left', padx=(5, 0))
        for widget in (self._box, self._label):
            widget.bind('<Button-1>', self._toggle)
            widget.bind('<Enter>', lambda event: self._hover(True))
            widget.bind('<Leave>', lambda event: self._hover(False))
        try:
            self.variable.trace_add('write', lambda *args: self._draw())
        except AttributeError:
            self.variable.trace('w', lambda *args: self._draw())
        self._draw()

    def configure(self, cnf=None, **kwargs):
        if 'state' in kwargs:
            self._state = kwargs.pop('state')
            self._draw()
        if cnf is not None:
            return tk.Frame.configure(self, cnf, **kwargs)
        if kwargs:
            return tk.Frame.configure(self, **kwargs)
        return None

    config = configure

    def _hover(self, on):
        self._hovering = on
        self._draw()

    def _toggle(self, _event=None):
        if self._state == 'disabled':
            return 'break'
        self.variable.set(not bool(self.variable.get()))
        if self.command is not None:
            self.command()
        return 'break'

    def _draw(self):
        c = self._box
        c.delete('all')
        disabled = self._state == 'disabled'
        on = bool(self.variable.get())
        if on:
            fill = '#A7C4BE' if disabled else ACCENT
            c.create_rectangle(0, 0, 14, 14, fill=fill, outline=fill)
            c.create_line(3, 7, 6, 10, 11, 4, fill='#FFFFFF', width=2)
        else:
            fill = '#F4F5F7' if disabled else '#FFFFFF'
            outline = BORDER if disabled else ('#B9BCC4' if self._hovering else '#C9CBD2')
            c.create_rectangle(0, 0, 14, 14, fill=fill, outline=outline)
        self._label.configure(fg=FAINT if disabled else TEXT,
                              cursor='arrow' if disabled else 'hand2')


class PageStack(tk.Frame):
    """One visible page at a time; exposes the ttk.Notebook subset App uses."""

    def __init__(self, master=None, **kwargs):
        tk.Frame.__init__(self, master, bg=BG, **kwargs)
        self._pages = []
        self._titles = {}
        self._current = None
        self._callback = None
        self.rowconfigure(0, weight=1)
        self.columnconfigure(0, weight=1)

    def add(self, page, text=None):
        if text is not None:
            self._titles[page] = text
        if page not in self._pages:
            self._pages.append(page)
            page.grid(row=0, column=0, sticky='nsew')
        if self._current is None:
            self.select(page)
        else:
            self._current.tkraise()
        return page

    def hide(self, page):
        # The sidebar exposes every workspace page permanently.
        return None

    def select(self, page):
        if page not in self._pages:
            self.add(page)
        self._current = page
        page.tkraise()
        if self._callback is not None:
            self._callback(page)

    def current(self):
        return self._current

    def set_on_change(self, callback):
        self._callback = callback

    def tab(self, page, option=None, text=None):
        if text is not None:
            self._titles[page] = text
        if option in (None, 'text'):
            return self._titles.get(page, '')
        return ''


class SideNav(tk.Frame):
    """Left navigation rail with hand-drawn vector icons and an active bar."""

    def __init__(self, master=None, stack=None, items=None, **kwargs):
        tk.Frame.__init__(self, master, bg=SIDEBAR_BG, **kwargs)
        self.stack = stack
        self.items = list(items or [])
        self._rows = {}
        self._active = None
        self._build_brand()
        self._build_items()
        self._build_footer()

    def _build_brand(self):
        brand = tk.Frame(self, bg=SIDEBAR_BG)
        brand.pack(fill='x', padx=20, pady=(22, 26))
        mark = tk.Canvas(brand, width=30, height=30, bg=SIDEBAR_BG,
                         highlightthickness=0)
        mark.create_rectangle(0, 0, 30, 30, fill=ACCENT, outline=ACCENT)
        mark.create_text(15, 16, text='O', fill='#FFFFFF', font='AppMark')
        mark.pack(side='left')
        names = tk.Frame(brand, bg=SIDEBAR_BG)
        names.pack(side='left', padx=(10, 0))
        tk.Label(names, text='ODB2VTU-S', bg=SIDEBAR_BG, fg=TEXT,
                 font='AppFontBold', anchor='w').pack(fill='x')
        tk.Label(names, text='Workbench', bg=SIDEBAR_BG, fg=MUTED,
                 font='AppTiny', anchor='w').pack(fill='x')

    def _build_items(self):
        tk.Label(self, text='工作区 / WORKSPACE', bg=SIDEBAR_BG, fg=FAINT,
                 font='AppTag', anchor='w').pack(fill='x', padx=23, pady=(0, 8))
        for page, label, kind in self.items:
            self._add_row(page, label, kind)

    def _build_footer(self):
        foot = tk.Frame(self, bg=SIDEBAR_BG)
        foot.pack(side='bottom', fill='x', padx=20, pady=14)
        tk.Label(foot, text='v1.0.1', bg=SIDEBAR_BG, fg=TEXT,
                 font='AppSmallBold', anchor='w').pack(fill='x')
        tk.Label(foot, text='Linux · CentOS 7 · Tk', bg=SIDEBAR_BG, fg=FAINT,
                 font='AppTiny', anchor='w').pack(fill='x', pady=(2, 0))
        tk.Frame(self, bg=BORDER, height=1).pack(side='bottom', fill='x', padx=20)
        tk.Frame(self, bg=SIDEBAR_BG).pack(fill='both', expand=True)

    def _add_row(self, page, label, kind):
        holder = tk.Frame(self, bg=SIDEBAR_BG, cursor='hand2')
        holder.pack(fill='x')
        bar = tk.Frame(holder, bg=SIDEBAR_BG, width=3)
        bar.pack(side='left', fill='y')
        body = tk.Frame(holder, bg=SIDEBAR_BG, cursor='hand2')
        body.pack(side='left', fill='both', expand=True)
        icon = tk.Canvas(body, width=18, height=18, bg=SIDEBAR_BG,
                         highlightthickness=0, cursor='hand2')
        icon.pack(side='left', padx=(11, 10), pady=10)
        text = tk.Label(body, text=label, bg=SIDEBAR_BG, fg=MUTED,
                        font='AppNav', anchor='w', cursor='hand2')
        text.pack(side='left', fill='x', expand=True, pady=10)
        row = {'page': page, 'holder': holder, 'bar': bar, 'body': body,
               'icon': icon, 'label': text, 'kind': kind}
        self._rows[page] = row
        for widget in (holder, body, icon, text):
            widget.bind('<Button-1>', lambda event, p=page: self._navigate(p))
            widget.bind('<Enter>', lambda event, r=row: self._hover(r, True))
            widget.bind('<Leave>', lambda event, r=row: self._leave(event, r))
        self._paint(row, False, False)

    def _navigate(self, page):
        if self.stack is not None:
            self.stack.select(page)

    def _hover(self, row, on):
        if self._active is row['page']:
            return
        self._paint(row, False, on)

    def _leave(self, event, row):
        widget = row['holder'].winfo_containing(event.x_root, event.y_root)
        while widget is not None:
            if widget is row['holder']:
                return
            widget = getattr(widget, 'master', None)
        self._hover(row, False)

    def _paint(self, row, active, hover=False):
        bg = ACCENT_SUBTLE if active else (SIDEBAR_HOVER if hover else SIDEBAR_BG)
        fg = ACCENT if active else ('#3F4650' if hover else '#4B5563')
        for key in ('holder', 'body', 'icon', 'label'):
            row[key].configure(bg=bg)
        row['bar'].configure(bg=ACCENT if active else bg)
        row['label'].configure(fg=fg,
                               font='AppNavActive' if active else 'AppNav')
        self._draw_icon(row['icon'], row['kind'], fg)

    def set_active(self, page):
        self._active = page
        for key, row in self._rows.items():
            self._paint(row, key is page, False)

    @staticmethod
    def _draw_icon(canvas, kind, color):
        c = canvas
        c.delete('all')
        if kind == 'export':
            c.create_rectangle(2, 8, 16, 16, outline=color)
            c.create_line(9, 12, 9, 2, fill=color)
            c.create_line(6, 5, 9, 2, fill=color)
            c.create_line(12, 5, 9, 2, fill=color)
        elif kind == 'curve':
            c.create_line(2, 2, 2, 16, 16, 16, fill=color)
            c.create_line(4, 13, 7, 8, 11, 10, 15, 4, fill=color)
        elif kind == 'analysis':
            c.create_line(2, 16, 16, 16, fill=color)
            c.create_rectangle(4, 10, 7, 15, outline=color)
            c.create_rectangle(8, 6, 11, 15, outline=color)
            c.create_rectangle(12, 3, 15, 15, outline=color)
        elif kind == 'cpfem':
            c.create_oval(4, 4, 14, 14, outline=color)
            c.create_oval(7, 7, 11, 11, outline=color)
            for x1, y1, x2, y2 in ((9, 0, 9, 3), (9, 15, 9, 18),
                                   (0, 9, 3, 9), (15, 9, 18, 9)):
                c.create_line(x1, y1, x2, y2, fill=color)
        else:  # safety shield
            c.create_polygon(9, 1, 15, 4, 15, 9, 9, 17, 3, 9, 3, 4,
                             fill='', outline=color)
            c.create_line(6, 9, 8, 11, 12, 6, fill=color)


class App(tk.Tk):
    def __init__(self):
        # WM_CLASS must match StartupWMClass in the .desktop entry, otherwise
        # GNOME shows a second, generic Tk launcher while the window is open.
        super().__init__(className='odb2vtu-s-workbench')
        self.title('ODB2VTU-S Workbench v1.0.1 — Linux')
        self.geometry('1320x820')
        self.minsize(1080, 700)
        self.lang = 'zh'
        self._lang_widgets = []
        self.meta = None
        self.field_meta = None
        self.curve_meta = None
        self.selected_states = []
        self.proc_queue = queue.Queue()
        self.running = False

        self.abaqus_cmd = tk.StringVar(value=os.environ.get('ABAQUS_CMD', 'singularity exec /home/soft/abaqus2024.sif /opt/run_abaqus.sh'))
        self.odb_var = tk.StringVar()
        self.auto_out = tk.BooleanVar(value=True)
        self.custom_out_dir = tk.StringVar()
        self.output_file = tk.StringVar()
        self.inp_var = tk.StringVar()
        self.series_var = tk.BooleanVar(value=False)
        self.mises_var = tk.BooleanVar(value=False)
        self.ipf_var = tk.BooleanVar(value=False)
        self.ipf_dir = tk.StringVar(value='Z')
        self.bbox_var = tk.StringVar()
        self.delta_var = tk.BooleanVar(value=False)
        self.delta_field = tk.StringVar()
        self.gnd_diff_var = tk.BooleanVar(value=False)
        self.gnd_dat_var = tk.StringVar()
        self.gnd_mode_var = tk.StringVar(value='仅18滑移系 / 18 slips only')
        self.gnd_slide_diff_var = tk.BooleanVar(value=False)
        self.gnd_slide_ref_var = tk.StringVar(value='滑动第一帧 / First sliding frame')
        self.frame_policy_var = tk.StringVar(value='合并/保留既有帧 / Merge')
        self.field_policy_var = tk.StringVar(value='合并/保留既有变量 / Merge')
        self.compatibility_mode_var = tk.StringVar(value='快速兼容（推荐）')
        self.write_mode_var = tk.BooleanVar(value=False)
        self.cleanup_removed_var = tk.BooleanVar(value=False)

        self._style()
        self._build_shell()
        self.nb = self.content
        self.export_tab = ttk.Frame(self.content)
        self.curve_tab = ttk.Frame(self.content)
        self.analysis_tab = ttk.Frame(self.content)
        self.cpfem_tab = ttk.Frame(self.content)
        self.safety_tab = ttk.Frame(self.content)
        self.nb.add(self.export_tab, text='数据导出 / Data Export')
        self.nb.add(self.curve_tab, text='曲线数据 / Curve Data')
        self.nb.add(self.analysis_tab, text='场变量分析 / Field Analysis')
        self.nb.add(self.cpfem_tab, text='摩擦 CPFEM / PEEQCP')
        self.nb.add(self.safety_tab, text='数据诊断与安全恢复 / Audit & Recovery')
        self._build_export_tab()
        self._build_curve_tab()
        self._build_analysis_tab()
        self._build_cpfem_tab()
        self._build_safety_tab()
        self._build_sidebar()
        self._build_app_menu()
        self._snapshot_ui_labels()
        self._apply_language()
        self.after(100, self._drain_queue)

    def _build_shell(self):
        self.status_var = tk.StringVar(value='就绪')
        self.page_meta = {}
        self.sidenav = None
        outer = tk.Frame(self, bg=BG)
        outer.pack(fill='both', expand=True)
        self.sidebar = tk.Frame(outer, bg=SIDEBAR_BG, width=236)
        self.sidebar.pack(side='left', fill='y')
        self.sidebar.pack_propagate(False)
        self.main = tk.Frame(outer, bg=BG)
        self.main.pack(side='left', fill='both', expand=True)
        self._build_topbar()
        self._build_statusbar()
        self.content = PageStack(self.main)
        self.content.pack(fill='both', expand=True)

    def _build_statusbar(self):
        bar = tk.Frame(self.main, bg=BG)
        bar.pack(side='bottom', fill='x')
        tk.Frame(bar, bg=BORDER, height=1).pack(side='top', fill='x')
        inner = tk.Frame(bar, bg=BG)
        inner.pack(fill='x', padx=26, pady=7)
        dot = tk.Canvas(inner, width=8, height=8, bg=BG, highlightthickness=0)
        dot.create_oval(1, 1, 7, 7, fill=ACCENT, outline=ACCENT)
        dot.pack(side='left', padx=(0, 7))
        tk.Label(inner, textvariable=self.status_var, bg=BG, fg=MUTED,
                 font='AppSmall', anchor='w').pack(side='left')
        tk.Label(inner, text='ODB2VTU-S  v1.0.1  ·  Linux', bg=BG, fg=FAINT,
                 font='AppSmall', anchor='e').pack(side='right')

    def _build_sidebar(self):
        items = [
            (self.export_tab, '数据导出 / Export', 'export'),
            (self.curve_tab, '曲线数据 / Curve Data', 'curve'),
            (self.analysis_tab, '场变量分析 / Field Analysis', 'analysis'),
            (self.cpfem_tab, '摩擦 CPFEM 后处理 / Friction CPFEM', 'cpfem'),
            (self.safety_tab, '诊断与恢复 / Audit & Recovery', 'safety'),
        ]
        self.page_meta = {
            self.export_tab: ('数据导出', 'Data export',
                              '将 Abaqus ODB 场变量导出为 VTU / PVD 时间序列',
                              'Export Abaqus ODB field output to VTU / PVD time series'),
            self.curve_tab: ('曲线数据', 'Curve data',
                             '提取 History 曲线并导出 CSV',
                             'Extract history curves and export CSV'),
            self.analysis_tab: ('场变量分析', 'Field analysis',
                                '晶粒排序、极值带与区域统计',
                                'Grain ranking, extreme bands and regional statistics'),
            self.cpfem_tab: ('摩擦 CPFEM 后处理', 'Friction CPFEM',
                             '逐帧累积 PEEQCP 并安全写回 ODB',
                             'Accumulate PEEQCP per frame and write back safely'),
            self.safety_tab: ('诊断与安全恢复', 'Audit & recovery',
                              '只读诊断、无损迁移与独立目录恢复',
                              'Read-only audit, lossless migration and safe recovery'),
        }
        self.sidenav = SideNav(self.sidebar, stack=self.content, items=items)
        self.sidenav.pack(fill='both', expand=True)
        self.content.set_on_change(self._on_page_change)
        self._on_page_change(self.content.current())

    def _on_page_change(self, page):
        meta = self.page_meta.get(page) if hasattr(self, 'page_meta') else None
        if meta is not None:
            zh = self.lang == 'zh'
            self.page_title_var.set(meta[0] if zh else meta[1])
            self.page_sub_var.set(meta[2] if zh else meta[3])
        if getattr(self, 'sidenav', None) is not None:
            self.sidenav.set_active(page)

    def _build_app_menu(self):
        # Rebuild the Tk native menu on language changes; callbacks remain unchanged.
        old = getattr(self, 'app_menu', None)
        bar = tk.Menu(self)
        edit = tk.Menu(bar, tearoff=False)
        edit.add_command(label=translate('曲线数据 / Curve Data', self.lang), command=lambda: self.open_work_page(self.curve_tab))
        edit.add_command(label=translate('场变量分析 / Field Analysis', self.lang), command=lambda: self.open_work_page(self.analysis_tab))
        edit.add_separator()
        edit.add_command(label=translate('摩擦 CPFEM 后处理 / History & PEEQCP', self.lang), command=lambda: self.open_work_page(self.cpfem_tab))
        bar.add_cascade(label=translate('编辑 / Edit', self.lang), menu=edit)
        tools = tk.Menu(bar, tearoff=False)
        tools.add_command(label=translate('诊断与安全恢复 / Audit & Safe Recovery', self.lang), command=lambda: self.open_work_page(self.safety_tab))
        bar.add_cascade(label=translate('工具 / Tools', self.lang), menu=tools)
        view = tk.Menu(bar, tearoff=False)
        view.add_command(label=translate('返回导出 / Export', self.lang), command=lambda: self.open_work_page(self.export_tab))
        bar.add_cascade(label=translate('视图 / View', self.lang), menu=view)
        self.config(menu=bar)
        self.app_menu = bar
        if old is not None:
            old.destroy()

    def _snapshot_ui_labels(self):
        # Snapshot immutable source text. Do not overwrite widget data-bound variables.
        def visit(widget):
            try:
                text = widget.cget('text')
                if isinstance(text, str) and text:
                    self._lang_widgets.append((widget, text))
            except (tk.TclError, AttributeError):
                pass
            for child in widget.winfo_children():
                visit(child)
        visit(self)
        self._tab_source_labels = {
            tab: self.nb.tab(tab, 'text')
            for tab in (self.export_tab, self.curve_tab, self.analysis_tab,
                        self.cpfem_tab, self.safety_tab)
        }

    def _apply_language(self):
        for widget, original in self._lang_widgets:
            try: widget.configure(text=translate(original, self.lang))
            except tk.TclError: pass
        for tab, original in self._tab_source_labels.items():
            self.nb.tab(tab, text=translate(original, self.lang))
        self._build_app_menu()
        self.title('ODB2VTU-S 统一工作台 v1.0.1 — Linux' if self.lang == 'zh'
                   else 'ODB2VTU-S Workbench v1.0.1 — Linux')
        if getattr(self, 'language_var', None) is not None:
            self.language_var.set('中文' if self.lang == 'zh' else 'English')
        # Display-only combobox text; backend uses stable selected indices.
        options = (
            (self.gnd_mode_cb, ('仅18滑移系','18滑移系+9方向'), ('18 slip systems only','18 slips + 9 directions')),
            (self.gnd_slide_ref_cb, ('滑动第一帧','滑动前一步最后帧'),
                                     ('First sliding frame','Last frame of preceding step')),
            (self.frame_policy_cb, ('合并／保留既有帧','同步当前所选帧'),
                                   ('Merge / preserve existing frames','Sync selected frames')),
            (self.field_policy_cb, ('合并／保留已有字段','同步当前所选字段'),
                                   ('Merge / preserve existing fields','Sync selected fields')),
            (self.compatibility_mode_cb, ('标准增量（已有 Manifest）','快速兼容（推荐）','严格验证（逐帧核对数值）'),
                                         ('Standard incremental','Fast compatible (recommended)','Strict numeric verification')),
        )
        for widget, chinese, english in options:
            index = widget.current()
            widget.configure(values=chinese if self.lang == 'zh' else english)
            widget.current(max(index, 0))
        if self.cpfem_status.get() in ('Waiting / 等待操作','等待操作','Waiting'):
            self.cpfem_status.set(translate('Waiting / 等待操作', self.lang))
        if self.status_var.get() in ('就绪', 'Ready'):
            self.status_var.set('就绪' if self.lang == 'zh' else 'Ready')
        if getattr(self, 'content', None) is not None:
            self._on_page_change(self.content.current())

    def _m(self, chinese, english):
        return chinese if self.lang == 'zh' else english

    def _change_language(self, _event=None):
        selected = self.language_var.get()
        lang = 'en' if selected == 'English' else 'zh'
        if lang != self.lang:
            self.lang = lang
            self._apply_language()

    def open_work_page(self, tab):
        self.nb.select(tab)

    def _build_cpfem_tab(self):
        parent = self.cpfem_tab
        f = tk.Frame(parent, bg=BG)
        f.pack(fill='both', expand=True, padx=24, pady=(16, 10))
        self.cpfem_odb = tk.StringVar()
        self.cpfem_out = tk.StringVar()
        self.cpfem_status = tk.StringVar(value='Waiting / 等待操作')
        src = Section(f, text='数据源 / Source'); src.pack(fill='x', pady=(0,10))
        r = ttk.Frame(src); r.pack(fill='x', pady=3)
        ttk.Label(r, text='摩擦 ODB / Source ODB', width=24).pack(side='left')
        ttk.Entry(r, textvariable=self.cpfem_odb).pack(side='left', fill='x', expand=True)
        ttk.Button(r, text='浏览...', command=self._cpfem_pick).pack(side='left', padx=(8,0))
        r = ttk.Frame(src); r.pack(fill='x', pady=3)
        ttk.Label(r, text='输出文件夹 / Output root', width=24).pack(side='left')
        ttk.Entry(r, textvariable=self.cpfem_out).pack(side='left', fill='x', expand=True)
        ttk.Button(r, text='浏览...', command=self._cpfem_pick_out).pack(side='left', padx=(8,0))

        ops = Section(f, text='PEEQCP 操作 / Operations'); ops.pack(fill='x', pady=(0,10))
        hint = ttk.Label(ops, text='逐帧累积 PEEQCP，目标帧按各摩擦循环的 T0/T25/T50/T75/T100 选取。',
                         style='Muted.TLabel', justify='left')
        hint.pack(anchor='w', pady=(0,10))
        auto_wrap(hint)
        buttons=ttk.Frame(ops); buttons.pack(fill='x')
        ttk.Button(buttons, text='② 计算 PEEQCP', style='Primary.TButton',
                   command=lambda:self._cpfem_run('peeq_export')).pack(side='left')
        ttk.Button(buttons, text='③ 写回 PEEQCP 到 ODB', style='Danger.TButton',
                   command=lambda:self._cpfem_run('peeq_inject')).pack(side='left', padx=8)
        ttk.Button(buttons, text='④ 检查 PEEQCP',
                   command=lambda:self._cpfem_run('peeq_check')).pack(side='left')
        ttk.Label(ops, textvariable=self.cpfem_status, style='Muted.TLabel').pack(anchor='w', pady=(10,0))

        logbox = Section(f, text='日志 / Log'); logbox.pack(fill='both', expand=True)
        self.cpfem_log = tk.Text(logbox, height=6, wrap='none'); self.cpfem_log.pack(fill='both',expand=True)

    def curve_export_friction(self):
        # Existing, proven friction History exporter; one GUI entry under Curve Data.
        odb = self.curve_odb.get() or self.odb_var.get()
        if not odb or not Path(odb).is_file():
            messagebox.showerror('曲线数据' if self.lang == 'zh' else 'Curve Data',
                                 '请先选择有效 ODB' if self.lang == 'zh' else 'Select a valid ODB first')
            return
        if not CPFEM_MASTER_PY.is_file():
            messagebox.showerror('CPFEM', '缺少历史曲线后端' if self.lang == 'zh' else 'History backend is missing')
            return
        out = self.cpfem_out.get() or str(Path(odb).parent)
        self.run_backend([CPFEM_MASTER_PY, '--operation','history','--odb',odb,'--outroot',out],
                         self.curve_log, None, '导出摩擦专用曲线' if self.lang == 'zh' else 'Export friction curves')

    def _cpfem_pick(self):
        p=filedialog.askopenfilename(filetypes=[('ODB','*.odb')])
        if p:self.cpfem_odb.set(p);self.cpfem_out.set(self.cpfem_out.get() or str(Path(p).parent))

    def _cpfem_pick_out(self):
        p=filedialog.askdirectory()
        if p:self.cpfem_out.set(p)

    def _cpfem_run(self, op):
        odb=self.cpfem_odb.get() or self.odb_var.get()
        out=self.cpfem_out.get() or (str(Path(odb).parent) if odb else '')
        if not odb or not Path(odb).is_file() or not out:
            messagebox.showerror('CPFEM',self._m('请选择有效 ODB 和输出目录','Select a valid ODB and output directory'));return
        if not CPFEM_MASTER_PY.is_file():
            messagebox.showerror('CPFEM',self._m('缺少 CPFEM 后端: abaqus_postprocess_master.py','Missing CPFEM backend: abaqus_postprocess_master.py'));return
        if op=='peeq_inject' and not messagebox.askyesno(self._m('危险：写回确认','Danger: ODB Write-back'),self._m('此操作会修改 ODB！请先备份 ODB 并关闭查看器。确认继续？','This modifies the ODB. Back it up and close all viewers. Continue?')):
            return
        self.cpfem_odb.set(odb);self.cpfem_out.set(out)
        def done(rc):
            self.cpfem_status.set(self._m('已完成','Completed') if rc==0 else self._m('失败 rc=%s','FAILED rc=%s')%rc)
            if rc != 0:messagebox.showerror('CPFEM',self._m('操作失败；请查看日志，返回码 %s','Operation failed. See log. Exit code %s')%rc)
            elif op=='peeq_inject':messagebox.showinfo('CPFEM',self._m('写回完成，请重新打开 ODB 验证','Write-back complete; reopen the ODB to verify'))
        self.cpfem_status.set(self._m('正在执行：','Running: ')+op)
        self.run_backend([CPFEM_MASTER_PY,'--operation',op,'--odb',odb,'--outroot',out],self.cpfem_log,done,'CPFEM '+op)

    def _build_safety_tab(self):
        parent=self.safety_tab
        host,f=self._make_scrollable_pane(parent,padding=0)
        host.pack(fill='both',expand=True,padx=24,pady=(16,8))
        self.safety_pvd=tk.StringVar()
        self.safety_fields=tk.StringVar(value='U,UR,SDV27,SDV49')
        self.safety_confirm=tk.BooleanVar(value=False)

        target=Section(f,text='审计目标 / Target'); target.pack(fill='x',pady=(0,10))
        r=ttk.Frame(target);r.pack(fill='x',pady=3)
        ttk.Label(r,text='PVD 文件',width=16).pack(side='left')
        ttk.Entry(r,textvariable=self.safety_pvd).pack(side='left',fill='x',expand=True)
        ttk.Button(r,text='浏览...',command=self._safety_pick).pack(side='left',padx=(8,0))
        ttk.Label(target,text='从 ODB 补充的原生字段 / Missing native fields (comma separated)',
                  style='Muted.TLabel').pack(anchor='w',pady=(10,4))
        ttk.Entry(target,textvariable=self.safety_fields).pack(fill='x')
        ttk.Button(target,text='1. 全量只读诊断（无需 ODB） / Full Audit',
                   command=self._safety_audit).pack(anchor='w',pady=(10,0))

        rec=Section(f,text='安全恢复 / Safe recovery'); rec.pack(fill='x',pady=(0,10))
        rec_hint = ttk.Label(rec,text='原 ODB/VTU/PVD/Manifest 均保持只读，恢复结果写入独立的 RECOVERED_SAFE 目录，绝不直接替换原目录。',
                             style='Muted.TLabel',justify='left')
        rec_hint.pack(anchor='w',pady=(0,10))
        auto_wrap(rec_hint)
        r=ttk.Frame(rec);r.pack(fill='x')
        ttk.Button(r,text='2. ODB 预检查 / CHECK ONLY',command=lambda:self._safety_recovery('check')).pack(side='left')
        ttk.Button(r,text='3. 安全恢复到新目录 / RESTORE',style='Primary.TButton',
                   command=lambda:self._safety_recovery('restore')).pack(side='right')
        Check(rec,text='已备份并完成预检查；只在全新恢复目录写入 / Confirmed backup and precheck',
                        variable=self.safety_confirm).pack(anchor='w',pady=(10,0))
        tk.Label(rec,text='恢复过程不会修改原始结果；请务必先完成第 2 步预检查。',
                 bg=BG,fg=DANGER,font='AppSmall',anchor='w').pack(fill='x',pady=(4,0))

        leg=Section(f,text='旧版无 Manifest 的迁移 / Legacy migration'); leg.pack(fill='x',pady=(0,10))
        leg_hint = ttk.Label(leg,text='需先在导出页面选好原始 ODB、实例和单元集。逐帧验证网格和原生场数值，然后复制到新的 MIGRATED_SAFE 目录。',
                             style='Muted.TLabel',justify='left')
        leg_hint.pack(anchor='w',pady=(0,10))
        auto_wrap(leg_hint)
        r=ttk.Frame(leg);r.pack(fill='x')
        ttk.Button(r,text='4. 旧版只读预检查 / Legacy CHECK',command=lambda:self._legacy_migration('check')).pack(side='left')
        ttk.Button(r,text='5. 迁移至新目录 / Legacy MIGRATE',style='Danger.TButton',
                   command=lambda:self._legacy_migration('migrate')).pack(side='right')

        logbox=Section(f,text='日志 / Log'); logbox.pack(fill='both',expand=True)
        self.safety_log=tk.Text(logbox,height=8,wrap='none');self.safety_log.pack(fill='both',expand=True)

    def _safety_pick(self):
        p=filedialog.askopenfilename(filetypes=[('PVD','*.pvd')])
        if p:self.safety_pvd.set(p)

    def _safety_valid(self):
        p=self.safety_pvd.get()
        if not p.lower().endswith('.pvd') or not Path(p).is_file():
            messagebox.showerror(self._m('数据安全','Data Safety'),self._m('请选择存在的 PVD 文件','Select an existing PVD file'));return False
        return True

    def _safety_audit(self):
        if not self._safety_valid():return
        if self.running:
            messagebox.showwarning(self._m('忙碌','Busy'),self._m('请等待当前任务结束','Wait for the current task to finish'));return
        cmd=[sys.executable,str(AUDIT_PY),self.safety_pvd.get(),'--max-scan','999999','--report',str(WORK_DIR/'ODB2VTUS_full_audit.json')]
        self._run_system_task(cmd,self.safety_log,'Read-only audit')

    def _run_system_task(self,cmd,log,title):
        self.running=True;self.status_var.set(title)
        log.insert('end','$ '+' '.join(shlex.quote(str(x)) for x in cmd)+'\n')
        def worker():
            rc=-1
            try:
                p=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,universal_newlines=True,bufsize=1)
                for line in p.stdout:self.proc_queue.put(('log',log,line))
                rc=p.wait()
            except Exception as ex:self.proc_queue.put(('log',log,'ERROR: %s\n'%ex))
            self.proc_queue.put(('done',None,rc))
        threading.Thread(target=worker,daemon=True).start()

    def _safety_recovery(self,mode):
        if not self._safety_valid():return
        import re
        fields=self.safety_fields.get().strip()
        if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*(,[A-Za-z][A-Za-z0-9_]*)*',fields):
            messagebox.showerror(self._m('数据安全','Data Safety'),self._m('仅支持逗号分隔的原生变量名，如 U,UR,SDV27,SDV49','Comma-separated native field names only, e.g. U,UR,SDV27,SDV49'));return
        if mode=='restore' and (not self.safety_confirm.get() or not messagebox.askyesno(self._m('确认安全恢复','Confirm recovery'),self._m('确认已备份且预检查成功？只向独立 RECOVERED_SAFE 目录写入，不修改原始结果。','Backed up and passed CHECK ONLY? Writes only to a new RECOVERED_SAFE folder.'))):
            return
        if not RECOVERY_PY.exists():messagebox.showerror(self._m('数据安全','Data Safety'),self._m('恢复后端缺失','Recovery backend is missing'));return
        self.run_backend([RECOVERY_PY,'--mode',mode,'--pvd',self.safety_pvd.get(),'--fields',fields],self.safety_log,None,'Safe recovery '+mode)

    def _legacy_migration(self,mode):
        if not self._safety_valid():return
        odb=self.odb_var.get()
        inst=self.instance_cb.get()
        if not Path(odb).is_file() or not inst:
            messagebox.showerror(self._m('旧版迁移','Legacy Migration'),self._m('请在导出页先选原 ODB 并读取实例。','Select the original ODB and instance in Export first.'));return
        if mode=='migrate' and (not self.safety_confirm.get() or not messagebox.askyesno(
            self._m('确认无损迁移','Confirm safe migration'),
            self._m('预检查是否已通过？将完整复制原始结果至独立 MIGRATED_SAFE 目录，原文件不变。',
                    'Has precheck passed? Copy all VTUs to a separate MIGRATED_SAFE folder?'))):
            return
        args=[LEGACY_PY,'--mode',mode,'--odb',odb,'--instance',inst,'--pvd',self.safety_pvd.get()]
        region=self.set_cb.get()
        if region and region != WHOLE:
            args += ['--element-set','__ALL_GRAINS__' if region == ALL_GRAINS else region]
        if self.bbox_var.get().strip():args += ['--bbox',self.bbox_var.get().strip()]
        self.run_backend(args,self.safety_log,None,'Legacy migration '+mode)

    def _style(self):
        init_theme_fonts(self)
        self.configure(bg=BG)
        s = ttk.Style(self)
        try: s.theme_use('clam')
        except Exception: pass

        s.configure('.', font='AppFont', background=BG, foreground=TEXT)
        s.configure('TFrame', background=BG)
        s.configure('Page.TFrame', background=BG)
        s.configure('Section.TFrame', background=BG)
        s.configure('TLabel', background=BG, foreground=TEXT)
        s.configure('Muted.TLabel', background=BG, foreground=MUTED)
        s.configure('Tag.TLabel', background=BG, foreground=FAINT, font='AppTag')
        s.configure('Title.TLabel', background=BG, foreground=TEXT, font='AppTitle')

        s.configure('TButton', font='AppFont', padding=(13, 7), relief='solid',
                    borderwidth=1, background='#FFFFFF', foreground=TEXT,
                    bordercolor=BORDER, lightcolor='#FFFFFF', darkcolor='#FFFFFF',
                    focusthickness=0, focuscolor=BG)
        s.map('TButton',
              background=[('disabled', '#F4F5F7'), ('pressed', '#F1F2F4'),
                          ('active', '#F7F7F8')],
              foreground=[('disabled', FAINT)],
              bordercolor=[('disabled', BORDER), ('active', '#C9CBD2')],
              lightcolor=[('active', '#F7F7F8'), ('pressed', '#F1F2F4')],
              darkcolor=[('active', '#F7F7F8'), ('pressed', '#F1F2F4')])
        s.configure('SecondarySmall.TButton', font='AppSmall', padding=(10, 5))
        s.configure('Small.TButton', font='AppSmall', padding=(6, 4))

        s.configure('Primary.TButton', font='AppFontBold', padding=(18, 9),
                    relief='flat', borderwidth=1, background=ACCENT,
                    foreground='#FFFFFF', bordercolor=ACCENT,
                    lightcolor=ACCENT, darkcolor=ACCENT,
                    focusthickness=0, focuscolor=ACCENT)
        s.map('Primary.TButton',
              background=[('disabled', '#A7C4BE'), ('pressed', ACCENT_HOVER),
                          ('active', ACCENT_HOVER)],
              foreground=[('disabled', '#F2F6F5')],
              bordercolor=[('disabled', '#A7C4BE'), ('pressed', ACCENT_HOVER),
                           ('active', ACCENT_HOVER)],
              lightcolor=[('pressed', ACCENT_HOVER), ('active', ACCENT_HOVER)],
              darkcolor=[('pressed', ACCENT_HOVER), ('active', ACCENT_HOVER)])

        s.configure('Danger.TButton', font='AppFont', padding=(13, 7),
                    relief='solid', borderwidth=1, background='#FFFFFF',
                    foreground=DANGER, bordercolor='#E7C6C2',
                    lightcolor='#FFFFFF', darkcolor='#FFFFFF',
                    focusthickness=0, focuscolor=BG)
        s.map('Danger.TButton',
              background=[('active', DANGER_SUBTLE), ('pressed', '#F6DCD8')],
              bordercolor=[('active', DANGER)],
              lightcolor=[('active', DANGER_SUBTLE)],
              darkcolor=[('active', DANGER_SUBTLE)])

        s.configure('TEntry', font='AppFont', fieldbackground='#FFFFFF',
                    foreground=TEXT, background='#FFFFFF', bordercolor=BORDER,
                    lightcolor='#FFFFFF', darkcolor='#FFFFFF', insertcolor=TEXT,
                    padding=(7, 5), relief='flat', borderwidth=1)
        s.map('TEntry', bordercolor=[('focus', ACCENT)],
              lightcolor=[('focus', '#FFFFFF')],
              darkcolor=[('focus', '#FFFFFF')])

        s.configure('TCombobox', font='AppFont', fieldbackground='#FFFFFF',
                    foreground=TEXT, background='#FFFFFF', bordercolor=BORDER,
                    lightcolor='#FFFFFF', darkcolor='#FFFFFF', arrowcolor=MUTED,
                    padding=(6, 4), relief='flat', borderwidth=1)
        s.map('TCombobox',
              fieldbackground=[('readonly', '#FFFFFF'), ('disabled', '#F4F5F7')],
              foreground=[('disabled', FAINT)],
              bordercolor=[('focus', ACCENT), ('active', '#C9CBD2')],
              arrowcolor=[('active', ACCENT)],
              lightcolor=[('focus', '#FFFFFF')],
              darkcolor=[('focus', '#FFFFFF')])

        s.configure('TCheckbutton', font='AppFont', background=BG,
                    foreground=TEXT, focusthickness=0, focuscolor=BG,
                    padding=(0, 2))
        s.map('TCheckbutton', background=[('active', BG)],
              foreground=[('disabled', FAINT)])
        s.configure('TRadiobutton', font='AppFont', background=BG,
                    foreground=TEXT, focusthickness=0, focuscolor=BG)
        s.map('TRadiobutton', background=[('active', BG)])

        s.configure('Vertical.TScrollbar', background='#E9EAEE', troughcolor=BG,
                    bordercolor=BG, arrowcolor=MUTED, relief='flat',
                    borderwidth=0, arrowsize=10)
        s.map('Vertical.TScrollbar',
              background=[('active', '#D5D7DD')],
              arrowcolor=[('active', ACCENT)])
        s.configure('Horizontal.TScrollbar', background='#E9EAEE',
                    troughcolor=BG, bordercolor=BG, arrowcolor=MUTED,
                    relief='flat', borderwidth=0)

        s.configure('TSeparator', background=BORDER)
        s.configure('TPanedwindow', background=BG)
        try:
            s.configure('Sash', sashthickness=2, gripcount=0, background=BG,
                        bordercolor=BG, lightcolor=BG, darkcolor=BG)
        except Exception:
            pass
        s.configure('TNotebook', background=BG, borderwidth=0)
        s.configure('TNotebook.Tab', padding=(12, 6))

        # tk.Listbox / tk.Text / tk.Canvas do not follow ttk styles; seed their
        # appearance through the option database before any page is created.
        for pattern, value in (
                ('*Listbox.background', '#FFFFFF'),
                ('*Listbox.foreground', TEXT),
                ('*Listbox.selectBackground', ACCENT_SUBTLE),
                ('*Listbox.selectForeground', ACCENT),
                ('*Listbox.highlightThickness', 1),
                ('*Listbox.highlightBackground', BORDER),
                ('*Listbox.highlightColor', ACCENT),
                ('*Listbox.borderWidth', 0),
                ('*Listbox.relief', 'flat'),
                ('*Listbox.activestyle', 'none'),
                ('*Listbox.font', 'AppFont'),
                ('*Text.background', '#FFFFFF'),
                ('*Text.foreground', TEXT),
                ('*Text.insertBackground', TEXT),
                ('*Text.selectBackground', ACCENT_SUBTLE),
                ('*Text.selectForeground', TEXT),
                ('*Text.highlightThickness', 1),
                ('*Text.highlightBackground', BORDER),
                ('*Text.highlightColor', ACCENT),
                ('*Text.borderWidth', 0),
                ('*Text.relief', 'flat'),
                ('*Text.font', 'AppMono'),
                ('*Text.padx', 10),
                ('*Text.pady', 8),
                ('*TCombobox*Listbox.background', '#FFFFFF'),
                ('*TCombobox*Listbox.foreground', TEXT),
                ('*TCombobox*Listbox.selectBackground', ACCENT_SUBTLE),
                ('*TCombobox*Listbox.selectForeground', ACCENT),
                ('*TCombobox*Listbox.font', 'AppFont'),
                ('*TCombobox*Listbox.borderWidth', 0)):
            try: self.option_add(pattern, value)
            except Exception: pass

    def _make_scrollable_pane(self, parent, padding=8):
        """Create a vertically scrollable pane compatible with CentOS 7 / Tk 8.5."""
        host = tk.Frame(parent, bg=BG)
        canvas = tk.Canvas(host, bg=BG, highlightthickness=0, borderwidth=0)
        scroll = ttk.Scrollbar(host, orient='vertical', command=canvas.yview,
                               style='Vertical.TScrollbar')
        canvas.configure(yscrollcommand=scroll.set)
        canvas.pack(side='left', fill='both', expand=True)

        inner = tk.Frame(canvas, bg=BG, padx=padding, pady=padding)
        window_id = canvas.create_window((0, 0), window=inner, anchor='nw')

        def _sync_region(event=None):
            view = max(1, canvas.winfo_height())
            width = max(1, canvas.winfo_width())
            need = inner.winfo_reqheight()
            current = int(float(canvas.itemcget(window_id, 'height') or 0))
            if need <= view:
                if current != view:
                    canvas.itemconfigure(window_id, height=view)
                if scroll.winfo_ismapped():
                    scroll.pack_forget()
            else:
                # Auto height so late layout changes cannot clip the last row.
                if current != 0:
                    canvas.itemconfigure(window_id, height=0)
                if not scroll.winfo_ismapped():
                    scroll.pack(side='right', fill='y', before=canvas)
            canvas.configure(scrollregion=(0, 0, width, max(need, view)))

        def _sync_width(event):
            canvas.itemconfigure(window_id, width=max(1, event.width - 12))
            canvas.after_idle(_sync_region)

        inner.bind('<Configure>', _sync_region)
        canvas.bind('<Configure>', _sync_width)
        host.bind('<Map>', lambda e: canvas.after_idle(_sync_region))

        # Linux/X11 mouse wheel support while the pointer is over this pane.
        # Do not hijack wheel events from interactive/scrollable child widgets:
        # Listbox/Text should scroll themselves; Combobox/Entry should not move the page.
        blocked_wheel_classes = {
            'Listbox', 'Text', 'Entry', 'TEntry', 'Combobox', 'TCombobox',
            'Spinbox', 'TSpinbox', 'Treeview', 'Scale', 'TScale',
            'Scrollbar', 'TScrollbar'
        }

        def _page_wheel_allowed(event):
            try:
                return event.widget.winfo_class() not in blocked_wheel_classes
            except Exception:
                return True

        def _wheel_up(event):
            if not _page_wheel_allowed(event):
                return None
            canvas.yview_scroll(-3, 'units')
            return 'break'

        def _wheel_down(event):
            if not _page_wheel_allowed(event):
                return None
            canvas.yview_scroll(3, 'units')
            return 'break'

        def _bind_wheel(event):
            canvas.bind_all('<Button-4>', _wheel_up)
            canvas.bind_all('<Button-5>', _wheel_down)

        def _unbind_wheel(event):
            canvas.unbind_all('<Button-4>')
            canvas.unbind_all('<Button-5>')

        canvas.bind('<Enter>', _bind_wheel)
        canvas.bind('<Leave>', _unbind_wheel)
        inner.bind('<Enter>', _bind_wheel)
        inner.bind('<Leave>', _unbind_wheel)

        return host, inner

    def _build_topbar(self):
        header = tk.Frame(self.main, bg=BG)
        header.pack(side='top', fill='x')
        top = tk.Frame(header, bg=BG)
        top.pack(fill='x', padx=26, pady=(20, 0))
        self.page_title_var = tk.StringVar(value='数据导出')
        self.page_sub_var = tk.StringVar(value='')
        tk.Label(top, textvariable=self.page_title_var, bg=BG, fg=TEXT,
                 font='AppTitle', anchor='w').pack(side='left')
        tk.Label(top, text='ABAQUS 2024  ·  CENTOS 7', bg=BG, fg=FAINT,
                 font='AppTag', anchor='e').pack(side='right')
        tk.Label(header, textvariable=self.page_sub_var, bg=BG, fg=MUTED,
                 font='AppSubtitle', anchor='w').pack(fill='x', padx=26, pady=(3, 0))

        strip = tk.Frame(header, bg=BG)
        strip.pack(fill='x', padx=26, pady=(14, 16))
        tk.Label(strip, text='求解器 / SOLVER', bg=BG, fg=FAINT,
                 font='AppTag').pack(side='left', padx=(0, 10))
        ttk.Entry(strip, textvariable=self.abaqus_cmd).pack(
            side='left', fill='x', expand=True)
        ttk.Button(strip, text='检查环境 / Check', style='SecondarySmall.TButton',
                   command=self.check_env).pack(side='left', padx=(8, 0))
        tk.Label(strip, text='语言 / Language', bg=BG, fg=MUTED,
                 font='AppSmall').pack(side='left', padx=(18, 8))
        self.language_var = tk.StringVar(value='中文')
        self.language_cb = ttk.Combobox(strip, textvariable=self.language_var,
                                        state='readonly', values=('中文', 'English'),
                                        width=9)
        self.language_cb.pack(side='left')
        self.language_cb.bind('<<ComboboxSelected>>', self._change_language)
        tk.Frame(self.main, bg=BORDER, height=1).pack(side='top', fill='x')


    def _build_export_tab(self):
        root = self.export_tab
        bar = tk.Frame(root, bg=BG)
        bar.pack(side='bottom', fill='x', padx=24, pady=(0, 10))
        tk.Frame(bar, bg=BORDER, height=1).pack(fill='x', pady=(0, 10))
        actions = tk.Frame(bar, bg=BG); actions.pack(fill='x')
        pan = ttk.Panedwindow(root, orient='horizontal'); pan.pack(fill='both', expand=True, padx=(24, 8), pady=(16, 0))
        left_host, left = self._make_scrollable_pane(pan, padding=0)
        right_host, right = self._make_scrollable_pane(pan, padding=0)
        pan.add(left_host, weight=4); pan.add(right_host, weight=5)

        src = Section(left, text='数据源 / Source'); src.pack(fill='x', pady=(0,10))
        row = ttk.Frame(src); row.pack(fill='x')
        ttk.Entry(row, textvariable=self.odb_var).pack(side='left', fill='x', expand=True)
        ttk.Button(row, text='选择 ODB', command=self.browse_odb).pack(side='left', padx=(5,0))
        row2 = ttk.Frame(src); row2.pack(fill='x', pady=(5,0))
        row2.columnconfigure(1, weight=1); row2.columnconfigure(2, weight=1)
        ttk.Button(row2, text='读取元数据', command=self.read_metadata).grid(row=0,column=0,sticky='w')
        self.instance_cb = ttk.Combobox(row2, state='readonly'); self.instance_cb.grid(row=0,column=1,sticky='ew',padx=(5,5))
        self.instance_cb.bind('<<ComboboxSelected>>', lambda e:self.refresh_sets())
        self.set_cb = ttk.Combobox(row2, state='readonly'); self.set_cb.grid(row=0,column=2,sticky='ew')

        out = Section(left, text='输出 / Output'); out.pack(fill='x', pady=(0,10))
        r = ttk.Frame(out); r.pack(fill='x')
        Check(r, text='自动匹配 ODB/ODB2VTU_Output', variable=self.auto_out, command=self.refresh_output_path).pack(side='left')
        ttk.Button(r, text='选择输出文件夹', command=self.choose_output_dir).pack(side='left', padx=8)
        r2=ttk.Frame(out); r2.pack(fill='x', pady=(5,0))
        ttk.Entry(r2, textvariable=self.output_file).pack(side='left', fill='x', expand=True)
        ttk.Button(r2, text='...', width=3, style='Small.TButton', command=self.choose_output_file).pack(side='left', padx=(5,0))

        state = Section(left, text='Step / Frame'); state.pack(fill='both', expand=True, pady=(0,10))
        top = ttk.Frame(state); top.pack(fill='x')
        top.columnconfigure(1, weight=1)
        ttk.Label(top,text='Step').grid(row=0,column=0,sticky='w')
        self.step_cb=ttk.Combobox(top,state='readonly',width=16)
        self.step_cb.grid(row=0,column=1,sticky='ew',padx=(5,8))
        self.step_cb.bind('<<ComboboxSelected>>', lambda e:self.populate_frames())
        ttk.Label(top,text='Frame').grid(row=0,column=2,sticky='w')
        self.frame_cb=ttk.Combobox(top,state='readonly',width=6)
        self.frame_cb.grid(row=0,column=3,sticky='ew',padx=(5,8))
        Check(top,text='PVD时间序列',variable=self.series_var,command=self._series_toggle).grid(row=0,column=4,sticky='w')

        sf=ttk.Frame(state); sf.pack(fill='both', expand=True, pady=(6,0))
        for _col in range(3):
            sf.columnconfigure(_col, weight=1, uniform='states')
        sf.rowconfigure(1, weight=1)
        ttk.Label(sf,text='Steps（Ctrl/Shift多选）').grid(row=0,column=0,sticky='w')
        ttk.Label(sf,text='公共Frame索引').grid(row=0,column=1,sticky='w',padx=(6,6))
        ttk.Label(sf,text='已选 Step/Frame').grid(row=0,column=2,sticky='w')
        self.series_steps=tk.Listbox(sf,selectmode='extended',height=5,exportselection=False,width=10)
        self.series_steps.grid(row=1,column=0,sticky='nsew',pady=(2,0))
        self.series_steps.bind('<<ListboxSelect>>', lambda e:self.populate_common_frames())
        self.common_frames=tk.Listbox(sf,selectmode='extended',height=5,exportselection=False,width=10)
        self.common_frames.grid(row=1,column=1,sticky='nsew',pady=(2,0),padx=(6,6))
        self.states_list=tk.Listbox(sf,selectmode='extended',height=5,exportselection=False,width=10)
        self.states_list.grid(row=1,column=2,sticky='nsew',pady=(2,0))
        buttons=ttk.Frame(state); buttons.pack(fill='x',pady=(5,0))
        btn_row1=ttk.Frame(buttons); btn_row1.pack(fill='x')
        ttk.Button(btn_row1,text='添加所选帧',command=lambda:self.add_series_frames(False)).pack(side='left')
        ttk.Button(btn_row1,text='添加全部公共帧',command=lambda:self.add_series_frames(True)).pack(side='left',padx=5)
        btn_row2=ttk.Frame(buttons); btn_row2.pack(fill='x',pady=(4,0))
        ttk.Button(btn_row2,text='移除',command=self.remove_states).pack(side='left')
        ttk.Button(btn_row2,text='清空',command=self.clear_states).pack(side='left',padx=5)

        # right fields / derived / log
        fields = Section(right,text='Field Output'); fields.pack(fill='x',expand=False,pady=(0,10))
        tb=ttk.Frame(fields); tb.pack(fill='x')
        ttk.Button(tb,text='读取当前帧变量',style='Small.TButton',command=self.read_fields).pack(side='left')
        ttk.Button(tb,text='全选',style='Small.TButton',command=lambda:self.fields_lb.select_set(0,'end')).pack(side='left',padx=5)
        ttk.Button(tb,text='清空',style='Small.TButton',command=lambda:self.fields_lb.selection_clear(0,'end')).pack(side='left')
        self.fields_lb=tk.Listbox(fields,selectmode='extended',exportselection=False,height=6); self.fields_lb.pack(fill='both',expand=True,pady=(6,0))
        self.fields_lb.bind('<<ListboxSelect>>', lambda e:self.update_export_summary())

        drv=Section(right,text='派生场 / Derived Fields'); drv.pack(fill='x',pady=(0,10))
        rr=ttk.Frame(drv); rr.pack(fill='x')
        Check(rr,text='Mises 应力',variable=self.mises_var).pack(side='left')
        Check(rr,text='Initial IPF (HCP Ti)',variable=self.ipf_var).pack(side='left',padx=12)
        rr_dir=ttk.Frame(drv); rr_dir.pack(fill='x',pady=(5,0))
        ttk.Label(rr_dir,text='IPF方向').pack(side='left')
        ttk.Combobox(rr_dir,textvariable=self.ipf_dir,values=['X','Y','Z'],state='readonly',width=6).pack(side='left',padx=4)
        rr2=ttk.Frame(drv); rr2.pack(fill='x',pady=(5,0))
        ttk.Label(rr2,text='INP').pack(side='left')
        ttk.Entry(rr2,textvariable=self.inp_var).pack(side='left',fill='x',expand=True,padx=5)
        ttk.Button(rr2,text='...',width=3,style='Small.TButton',command=self.browse_inp).pack(side='left')
        rr3=ttk.Frame(drv); rr3.pack(fill='x',pady=(5,0))
        ttk.Label(rr3,text='Bounding Box').pack(side='left')
        ttk.Entry(rr3,textvariable=self.bbox_var).pack(side='left',fill='x',expand=True,padx=5)
        bbox_hint = ttk.Label(drv,text='xmin,xmax,ymin,ymax,zmin,zmax',
                              style='Muted.TLabel')
        bbox_hint.pack(anchor='w',pady=(3,0))
        auto_wrap(bbox_hint)

        gnd=Section(right,text='GND增量 / GND Evolution'); gnd.pack(fill='x',pady=(0,10))
        Check(gnd,text='计算 gnd_field.dat 与 SDV11–28 差值',variable=self.gnd_diff_var).pack(anchor='w')
        gr1=ttk.Frame(gnd); gr1.pack(fill='x',pady=(4,0))
        ttk.Label(gr1,text='输出').pack(side='left')
        self.gnd_mode_cb=ttk.Combobox(gr1,textvariable=self.gnd_mode_var,state='readonly',values=['仅18滑移系 / 18 slips only','18滑移系+9方向 / 18 slips + 9 directions'])
        self.gnd_mode_cb.pack(side='left',fill='x',expand=True,padx=(6,0))

        gr2=ttk.Frame(gnd); gr2.pack(fill='x',pady=(4,0))
        ttk.Label(gr2,text='gnd_field.dat').pack(side='left')
        ttk.Entry(gr2,textvariable=self.gnd_dat_var).pack(side='left',fill='x',expand=True,padx=5)
        ttk.Button(gr2,text='...',width=3,style='Small.TButton',command=self.browse_gnd_dat).pack(side='left')
        Check(gnd,text='滑动起点差值（18滑移系）',variable=self.gnd_slide_diff_var).pack(anchor='w',pady=(7,0))
        gr3=ttk.Frame(gnd); gr3.pack(fill='x',pady=(4,0))
        ttk.Label(gr3,text='参考').pack(side='left')
        self.gnd_slide_ref_cb=ttk.Combobox(gr3,textvariable=self.gnd_slide_ref_var,state='readonly',values=[
            '滑动第一帧 / First sliding frame',
            '滑动前一步最后帧 / Previous-step last frame'])
        self.gnd_slide_ref_cb.pack(side='left',fill='x',expand=True,padx=(6,0))
        gnd_hint = ttk.Label(gnd,text='DAT差值：当前SDV11–28减去gnd_field.dat初始分配；滑动起点差值：当前SDV11–28减去固定参考帧。DAT差值可选输出「18滑移系」或「18滑移系+9方向」（后者额外输出 DGND_Dir01-09 九个 Burgers 方向增量）；滑动起点差值固定只输出18个滑移系。',foreground='#555',justify='left')
        gnd_hint.pack(anchor='w',pady=(6,0))
        auto_wrap(gnd_hint)

        diff=Section(right,text='差值 / Difference'); diff.pack(fill='x',pady=(0,10))
        Check(diff,text='启用目标帧-参考帧',variable=self.delta_var).pack(anchor='w')
        d1=ttk.Frame(diff); d1.pack(fill='x',pady=(4,0))
        ttk.Label(d1,text='差值变量 / Field').pack(side='left')
        self.delta_field_cb=ttk.Combobox(d1,textvariable=self.delta_field,state='readonly')
        self.delta_field_cb.pack(side='left',fill='x',expand=True,padx=(6,0))
        d2=ttk.Frame(diff); d2.pack(fill='x',pady=(4,0))
        ttk.Label(d2,text='参考 Step/Frame').pack(side='left')
        self.ref_step_cb=ttk.Combobox(d2,state='readonly')
        self.ref_step_cb.pack(side='left',fill='x',expand=True,padx=(6,4))
        self.ref_step_cb.bind('<<ComboboxSelected>>',lambda e:self.populate_ref_frames())
        self.ref_frame_cb=ttk.Combobox(d2,state='readonly',width=6); self.ref_frame_cb.pack(side='left')

        policy=Section(right,text='增量更新策略 / Incremental Update Policy'); policy.pack(fill='x',pady=(0,10))
        pr1=ttk.Frame(policy); pr1.pack(fill='x')
        ttk.Label(pr1,text='帧 / Frames').pack(side='left')
        self.frame_policy_cb=ttk.Combobox(
            pr1,textvariable=self.frame_policy_var,state='readonly',
            values=['合并/保留既有帧 / Merge','同步当前选择 / Sync'])
        self.frame_policy_cb.pack(side='left',fill='x',expand=True,padx=(6,0))
        pr2=ttk.Frame(policy); pr2.pack(fill='x',pady=(4,0))
        ttk.Label(pr2,text='变量 / Fields').pack(side='left')
        self.field_policy_cb=ttk.Combobox(
            pr2,textvariable=self.field_policy_var,state='readonly',
            values=['合并/保留既有变量 / Merge','同步当前变量 / Sync'])
        self.field_policy_cb.pack(side='left',fill='x',expand=True,padx=(6,0))
        cr=ttk.Frame(policy); cr.pack(fill='x',pady=(4,0))
        ttk.Label(cr,text='兼容模式 / Compatibility').pack(side='left')
        self.compatibility_mode_cb=ttk.Combobox(
            cr,textvariable=self.compatibility_mode_var,state='readonly',
            values=['标准增量（已有 Manifest）','快速兼容（推荐）','严格验证（逐帧核对数值）'])
        self.compatibility_mode_cb.pack(side='left',fill='x',expand=True,padx=(6,0))
        self.compatibility_mode_cb.current(1)
        self.in_place_cb = Check(
            policy,
            text='原位增量更新已有 VTU / In-place update existing VTUs (no new folder)',
            variable=self.write_mode_var,
            command=self.update_export_summary)
        self.in_place_cb.pack(anchor='w',pady=(7,0))
        self.in_place_cb.configure(state='disabled')
        self.compat_hint = ttk.Label(
            policy,
            text='安全复制模式：无 Manifest 的旧数据会复制到 MIGRATED_SAFE；勾选原位更新后不创建新数据目录，直接更新原 VTU。 / Safe-copy mode creates MIGRATED_SAFE for manifest-less legacy data; in-place mode updates the original VTUs without a new data directory.',
            foreground='#555', justify='left')
        self.compat_hint.pack(anchor='w',pady=(3,0))
        auto_wrap(self.compat_hint)
        pr2=ttk.Frame(policy); pr2.pack(fill='x',pady=(5,0))
        Check(
            pr2,text='同步帧时同时删除已移除帧的 VTU / Delete removed-frame VTU files',
            variable=self.cleanup_removed_var,
            command=self.update_export_summary).pack(side='left')
        merge_hint = ttk.Label(
            policy,
            text='Merge 为安全默认：未再次选择的旧帧/旧变量均保留；Sync 才执行删除语义。',
            foreground='#555',justify='left')
        merge_hint.pack(anchor='w',pady=(6,0))
        auto_wrap(merge_hint)

        summary_box=Section(right,text='选择摘要 / Selection Summary'); summary_box.pack(fill='both',expand=True,pady=(0,10))
        self.summary=tk.Text(summary_box,height=6,wrap='none',state='disabled')
        self.summary.pack(fill='both',expand=True)

        ttk.Button(actions,text='导出 VTU / PVD',style='Primary.TButton',command=self.run_export).pack(side='right')
        ttk.Button(actions,text='打开输出目录',command=lambda:self.open_folder(Path(self.output_file.get()).parent)).pack(side='right',padx=(0,8))
        ttk.Label(actions,text='VTU 可直接在 ParaView 中打开 / Opens directly in ParaView',style='Muted.TLabel').pack(side='left')

        msg_box=Section(right,text='输出信息 / Output Messages'); msg_box.pack(fill='both',expand=True)
        msg_head=ttk.Frame(msg_box); msg_head.pack(fill='x')
        ttk.Button(msg_head,text='清空 / Clear',command=lambda:self.log.delete('1.0','end')).pack(side='right')
        self.log=tk.Text(msg_box,height=6,wrap='none')
        self.log.pack(fill='both',expand=True,pady=(4,0))

        self.instance_cb.bind('<<ComboboxSelected>>', lambda e:(self.refresh_sets(),self.update_export_summary()))
        self.set_cb.bind('<<ComboboxSelected>>', lambda e:self.update_export_summary())
        self.step_cb.bind('<<ComboboxSelected>>', lambda e:(self.populate_frames(),self.update_export_summary()))
        self.frame_cb.bind('<<ComboboxSelected>>', lambda e:self.update_export_summary())
        for _v in (self.series_var,self.mises_var,self.ipf_var,self.ipf_dir,self.bbox_var,
                   self.delta_var,self.delta_field,self.gnd_diff_var,self.gnd_mode_var,
                   self.gnd_slide_diff_var,self.gnd_slide_ref_var,self.output_file,
                   self.frame_policy_var,self.field_policy_var,self.compatibility_mode_var,self.cleanup_removed_var):
            try: _v.trace_add('write', lambda *_: self.update_export_summary())
            except Exception: pass
        self.after_idle(self.update_export_summary)

    # ---------------- Curve tab ----------------
    def _build_curve_tab(self):
        root=self.curve_tab
        outer=ttk.Panedwindow(root,orient='horizontal'); outer.pack(fill='both',expand=True,padx=(24,8),pady=(16,8))
        left_host,left=self._make_scrollable_pane(outer,padding=0)
        right_host,right=self._make_scrollable_pane(outer,padding=0)
        outer.add(left_host,weight=4); outer.add(right_host,weight=5)
        src=Section(left,text='History Source'); src.pack(fill='x',pady=(0,10))
        self.curve_odb=tk.StringVar()
        r=ttk.Frame(src); r.pack(fill='x')
        ttk.Entry(r,textvariable=self.curve_odb,width=6).pack(side='left',fill='x',expand=True)
        ttk.Button(r,text='选择ODB',command=self.curve_browse_odb).pack(side='left',padx=5)
        ttk.Button(r,text='读取History元数据',command=self.curve_read_meta).pack(side='left')
        ttk.Label(src,text='Steps（Ctrl/Shift多选）').pack(anchor='w',pady=(6,0))
        self.curve_steps=tk.Listbox(src,selectmode='extended',height=4,exportselection=False); self.curve_steps.pack(fill='x')
        self.curve_steps.bind('<<ListboxSelect>>',lambda e:self.curve_refresh_regions())

        rg=Section(left,text='History Region / Section'); rg.pack(fill='x',pady=(0,10))
        self.curve_region=ttk.Combobox(rg,state='readonly'); self.curve_region.pack(fill='x')
        self.curve_region.bind('<<ComboboxSelected>>',lambda e:self.curve_refresh_vars())
        nf=ttk.Frame(rg); nf.pack(fill='x',pady=(5,0))
        ttk.Label(nf,text='Node ID').pack(side='left')
        self.curve_node=tk.StringVar(); ttk.Entry(nf,textvariable=self.curve_node,width=12).pack(side='left',padx=5)
        ttk.Button(nf,text='查找节点',command=self.curve_find_node).pack(side='left')

        cv=Section(left,text='Curve'); cv.pack(fill='x')
        self.curve_preset=tk.StringVar(value='Custom')
        presets=['Custom','RF1-U1','CF2-U2','RF2-U2','COF-Time','COF-U1','U2-Time']
        p=ttk.Combobox(cv,textvariable=self.curve_preset,values=presets,state='readonly'); p.pack(fill='x'); p.bind('<<ComboboxSelected>>',lambda e:self.curve_apply_preset())
        self.x_abs=tk.BooleanVar(); self.y_abs=tk.BooleanVar(); self.dedupe=tk.BooleanVar(value=True)
        rx=ttk.Frame(cv); rx.pack(fill='x',pady=(5,2))
        ttk.Label(rx,text='X').pack(side='left',padx=(0,5))
        self.curve_x=ttk.Combobox(rx,state='readonly'); self.curve_x.pack(side='left',fill='x',expand=True)
        Check(rx,text='|X|',variable=self.x_abs).pack(side='left',padx=(4,0))
        ry=ttk.Frame(cv); ry.pack(fill='x',pady=2)
        ttk.Label(ry,text='Y').pack(side='left',padx=(0,5))
        self.curve_y=ttk.Combobox(ry,state='readonly'); self.curve_y.pack(side='left',fill='x',expand=True)
        Check(ry,text='|Y|',variable=self.y_abs).pack(side='left',padx=(4,0))
        rr2=ttk.Frame(cv); rr2.pack(fill='x',pady=(8,0))
        self.x_scale=tk.StringVar(value='1'); self.y_scale=tk.StringVar(value='1'); self.x_off=tk.StringVar(value='0'); self.y_off=tk.StringVar(value='0')
        for i,(lab,var) in enumerate((('X 缩放 / X scale',self.x_scale),('X 偏移 / X offset',self.x_off),
                                      ('Y 缩放 / Y scale',self.y_scale),('Y 偏移 / Y offset',self.y_off))):
            row,col=divmod(i,2)
            ttk.Label(rr2,text=lab).grid(row=row,column=col*2,sticky='w',pady=3)
            ttk.Entry(rr2,textvariable=var,width=8).grid(row=row,column=col*2+1,sticky='ew',pady=3,padx=(5,16))
        rr2.columnconfigure(1,weight=1); rr2.columnconfigure(3,weight=1)
        Check(cv,text='去除Step边界重复点',variable=self.dedupe).pack(anchor='w',pady=(8,0))

        out=Section(right,text='输出 / Output'); out.pack(fill='x',pady=(0,10))
        self.curve_auto=tk.BooleanVar(value=True); self.curve_out=tk.StringVar()
        rr=ttk.Frame(out); rr.pack(fill='x')
        Check(rr,text='自动输出到 ODB/ODB2VTU_Output',variable=self.curve_auto,command=self.curve_update_out).pack(side='left')
        ttk.Button(rr,text='选择文件夹',command=self.curve_choose_folder).pack(side='left',padx=6)
        rr2=ttk.Frame(out); rr2.pack(fill='x',pady=5)
        ttk.Entry(rr2,textvariable=self.curve_out).pack(side='left',fill='x',expand=True)
        ttk.Button(rr2,text='...',width=3,style='Small.TButton',command=self.curve_choose_file).pack(side='left',padx=5)
        top=ttk.Frame(out); top.pack(fill='x',pady=(12,0))
        ttk.Button(top,text='导出摩擦专用 CSV',command=self.curve_export_friction).pack(side='left')
        ttk.Label(out,text='ALL / NORMAL / TANGENTIAL / DIAGNOSTIC',style='Muted.TLabel').pack(anchor='w',pady=(4,0))
        bot=ttk.Frame(out); bot.pack(fill='x',pady=(8,0))
        ttk.Button(bot,text='导出 CSV',style='Primary.TButton',command=self.curve_export).pack(side='right')
        logbox=Section(right,text='日志 / Log'); logbox.pack(fill='both',expand=True)
        self.curve_log=tk.Text(logbox,wrap='none',height=8); self.curve_log.pack(fill='both',expand=True)

    # ---------------- Analysis tab ----------------
    def _build_analysis_tab(self):
        root=self.analysis_tab
        bar=tk.Frame(root,bg=BG); bar.pack(side='bottom',fill='x',padx=24,pady=(0,10))
        tk.Frame(bar,bg=BORDER,height=1).pack(fill='x',pady=(0,10))
        actions=tk.Frame(bar,bg=BG); actions.pack(fill='x')
        ttk.Button(actions,text='运行分析',style='Primary.TButton',command=self.analysis_run).pack(side='right')
        ttk.Button(actions,text='打开输出目录',command=lambda:self.open_folder(self.a_out.get())).pack(side='right',padx=(0,8))
        ttk.Label(actions,text='分析结果写入独立文件夹 / Results go to a separate folder',style='Muted.TLabel').pack(side='left')
        pan=ttk.Panedwindow(root,orient='horizontal'); pan.pack(fill='both',expand=True,padx=(24,8),pady=(16,0))
        left_host,left=self._make_scrollable_pane(pan,padding=0)
        right_host,right=self._make_scrollable_pane(pan,padding=0)
        pan.add(left_host,weight=4); pan.add(right_host,weight=5)
        data=Section(left,text='数据状态 / Data state'); data.pack(fill='x',pady=(0,10))
        body=ttk.Frame(data); body.pack(fill='x')
        self.a_instance=ttk.Combobox(body,state='readonly')
        self.a_step=ttk.Combobox(body,state='readonly')
        self.a_frame=ttk.Combobox(body,state='readonly')
        self.a_field=ttk.Combobox(body,state='readonly')
        for i,(lab,w) in enumerate((('实例 / Instance',self.a_instance),('分析步 / Step',self.a_step),
                                    ('帧 / Frame',self.a_frame),('变量 / Field',self.a_field))):
            ttk.Label(body,text=lab,width=16).grid(row=i,column=0,sticky='w',pady=3)
            w.grid(row=i,column=1,sticky='ew',pady=3)
        body.columnconfigure(1,weight=1)
        self.a_step.bind('<<ComboboxSelected>>',lambda e:self.analysis_frames())
        ttk.Button(data,text='读取可分析变量',command=self.analysis_read_fields).pack(anchor='w',pady=(10,0))
        reg=Section(left,text='区域 / Region'); reg.pack(fill='x',pady=(0,10))
        self.a_bbox=tk.StringVar(); ttk.Entry(reg,textvariable=self.a_bbox).pack(fill='x')
        ttk.Label(reg,text='可选 Bounding Box: xmin,xmax,ymin,ymax,zmin,zmax',style='Muted.TLabel').pack(anchor='w',pady=(4,0))
        rank=Section(left,text='晶粒排序 / Grain ranking'); rank.pack(fill='x',pady=(0,10))
        self.a_top=tk.StringVar(value='10'); self.a_rank=tk.StringVar(value='mean'); self.a_dir=tk.StringVar(value='max'); self.a_band=tk.StringVar(value='5')
        for lab,var,values in (
                ('前 N 个晶粒 / Top N grains',self.a_top,None),
                ('排序统计量 / Rank statistic',self.a_rank,['mean','max','min']),
                ('方向 / Direction',self.a_dir,['max','min']),
                ('极值带 (%) / Extreme band',self.a_band,None)):
            rr=ttk.Frame(rank); rr.pack(fill='x',pady=3)
            ttk.Label(rr,text=lab,width=20).pack(side='left')
            if values is None:
                ttk.Entry(rr,textvariable=var).pack(side='left',fill='x',expand=True)
            else:
                ttk.Combobox(rr,textvariable=var,values=values,state='readonly').pack(side='left',fill='x',expand=True)
        out=Section(left,text='输出 / Output'); out.pack(fill='x')
        self.a_export_vtu=tk.BooleanVar(value=True); self.a_split=tk.BooleanVar(value=False); self.a_scope=tk.StringVar(value='top'); self.a_out=tk.StringVar()
        Check(out,text='同时导出分析 VTU',variable=self.a_export_vtu).pack(anchor='w',pady=2)
        rr=ttk.Frame(out); rr.pack(fill='x',pady=5); ttk.Label(rr,text='VTU范围',width=12).pack(side='left')
        ttk.Combobox(rr,textvariable=self.a_scope,values=['top','band','extreme','all'],state='readonly').pack(side='left',fill='x',expand=True)
        Check(out,text='每个选中晶粒单独导出VTU',variable=self.a_split).pack(anchor='w',pady=2)
        rr2=ttk.Frame(out); rr2.pack(fill='x',pady=(8,0)); ttk.Entry(rr2,textvariable=self.a_out).pack(side='left',fill='x',expand=True); ttk.Button(rr2,text='...',width=3,style='Small.TButton',command=self.analysis_choose_out).pack(side='left',padx=4)
        logbox=Section(right,text='分析结果 / Analysis Log'); logbox.pack(fill='both',expand=True)
        self.analysis_log=tk.Text(logbox,wrap='none',height=10); self.analysis_log.pack(fill='both',expand=True)

    # ---------------- shared process helpers ----------------
    def abaqus_prefix(self):
        cmd=self.abaqus_cmd.get().strip()
        if not cmd: raise ValueError('Abaqus command is empty.')
        return shlex.split(cmd) + ['python']

    def run_backend(self, args, log_widget, callback=None, title='Running'):
        if self.running:
            messagebox.showinfo(self._m('忙碌','Busy'),self._m('已有后台任务正在运行。','A backend task is already running.'))
            return
        self.running=True
        full=self.abaqus_prefix()+[str(x) for x in args]
        if log_widget:
            log_widget.insert('end','$ ' + ' '.join(shlex.quote(x) for x in full)+'\n')
            log_widget.see('end')
        self.status_var.set(title)
        def worker():
            rc=-1
            try:
                env=os.environ.copy()
                env['PYTHONUNBUFFERED']='1'
                p=subprocess.Popen(full,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,universal_newlines=True,bufsize=1,env=env)
                for line in p.stdout:
                    self.proc_queue.put(('log',log_widget,line))
                rc=p.wait()
            except Exception as exc:
                self.proc_queue.put(('log',log_widget,'ERROR: %s\n'%exc))
            self.proc_queue.put(('done',callback,rc))
        threading.Thread(target=worker,daemon=True).start()

    def _drain_queue(self):
        try:
            while True:
                item=self.proc_queue.get_nowait()
                if item[0]=='log':
                    w,line=item[1],item[2]
                    if w:
                        w.insert('end',line); w.see('end')
                elif item[0]=='done':
                    self.running=False
                    cb,rc=item[1],item[2]
                    self.status_var.set(self._m('已完成','Completed') if rc==0 else self._m('失败（返回码 %s）','Failed (rc=%s)')%rc)
                    if cb:
                        try: cb(rc)
                        except Exception as exc: messagebox.showerror('Error',str(exc))
        except queue.Empty: pass
        self.after(100,self._drain_queue)

    def check_env(self):
        # Do NOT use `python -c` here. Some site-specific Abaqus wrapper scripts
        # re-expand $@ and split the inline code at spaces/semicolons.
        # A real .py helper is robust through Singularity + run_abaqus.sh.
        helper = Path(__file__).resolve().parent / 'abaqus_env_check.py'
        full = self.abaqus_prefix() + [str(helper)]
        try:
            p = subprocess.run(
                full,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                universal_newlines=True,
                timeout=60
            )
            msg = 'Command: %s\nReturn code: %s\n\n%s\n%s' % (
                ' '.join(shlex.quote(x) for x in full),
                p.returncode,
                p.stdout,
                p.stderr
            )
            if p.returncode == 0:
                messagebox.showinfo('Environment', msg[:6000])
            else:
                messagebox.showerror('Environment', msg[:6000])
        except Exception as exc:
            messagebox.showerror('Environment', str(exc))

    # ---------------- Export tab logic ----------------
    def browse_odb(self):
        p=filedialog.askopenfilename(filetypes=[('Abaqus ODB','*.odb'),('All files','*')])
        if not p:return
        self.odb_var.set(p); self.curve_odb.set(p); self.try_match_inp(p); self.try_match_gnd(p); self.refresh_output_path(); self.curve_update_out(); self.analysis_default_out()
        self.meta=None; self.selected_states=[]; self.refresh_states_list()

    def try_match_inp(self,odb):
        p=Path(odb); cand=p.with_suffix('.inp')
        if cand.exists(): self.inp_var.set(str(cand))
        else:
            inps=list(p.parent.glob('*.inp'))
            if len(inps)==1:self.inp_var.set(str(inps[0]))

    def browse_inp(self):
        p=filedialog.askopenfilename(filetypes=[('Abaqus INP','*.inp'),('All files','*')])
        if p:self.inp_var.set(p)

    def try_match_gnd(self,odb):
        p=Path(odb); cand=p.parent/'gnd_field.dat'
        if cand.exists(): self.gnd_dat_var.set(str(cand))

    def browse_gnd_dat(self):
        p=filedialog.askopenfilename(filetypes=[('GND field DAT','*.dat'),('All files','*')])
        if p:self.gnd_dat_var.set(p)

    def auto_dir(self):
        if not self.odb_var.get():return ''
        d=Path(self.odb_var.get()).resolve().parent/'ODB2VTU_Output'; d.mkdir(exist_ok=True)
        return str(d)

    def choose_output_dir(self):
        d=filedialog.askdirectory()
        if d:self.custom_out_dir.set(d); self.auto_out.set(False); self.refresh_output_path()
    def choose_output_file(self):
        ext='.pvd' if self.series_var.get() else '.vtu'
        p=filedialog.asksaveasfilename(defaultextension=ext,filetypes=[('Output','*'+ext),('All','*')])
        if p:self.output_file.set(p); self.auto_out.set(False); self.custom_out_dir.set(str(Path(p).parent))
    def refresh_output_path(self):
        odb=self.odb_var.get()
        if not odb:return
        d=self.auto_dir() if self.auto_out.get() or not self.custom_out_dir.get() else self.custom_out_dir.get()
        Path(d).mkdir(parents=True,exist_ok=True)
        stem=Path(odb).stem
        self.output_file.set(str(Path(d)/(stem+('_series.pvd' if self.series_var.get() else '_selected.vtu'))))
        self.update_export_summary()
    def _series_toggle(self):
        # In-place update applies only to an existing PVD time series.
        if not self.series_var.get():
            self.write_mode_var.set(False)
            if hasattr(self, 'in_place_cb'):
                self.in_place_cb.configure(state='disabled')
        elif hasattr(self, 'in_place_cb'):
            self.in_place_cb.configure(state='normal')
        self.refresh_output_path()
        self.update_export_summary()

    def read_metadata(self):
        odb=self.odb_var.get()
        if not Path(odb).exists(): messagebox.showerror('ODB','请选择有效ODB'); return
        def done(rc):
            if rc!=0 or not META_JSON.exists(): return
            self.meta=json.loads(META_JSON.read_text())
            inst=list(self.meta['instances']); steps=list(self.meta['steps'])
            self.instance_cb['values']=inst; self.a_instance['values']=inst
            if inst:self.instance_cb.current(0); self.a_instance.current(0); self.refresh_sets()
            self.step_cb['values']=steps; self.ref_step_cb['values']=steps; self.a_step['values']=steps
            self.series_steps.delete(0,'end')
            for s in steps:self.series_steps.insert('end',s)
            if steps:
                self.step_cb.current(0); self.ref_step_cb.current(0); self.a_step.current(0); self.series_steps.selection_set(0)
                self.populate_frames(); self.populate_ref_frames(); self.analysis_frames(); self.populate_common_frames()
            self.analysis_default_out(); self.log.insert('end','Metadata ready.\n'); self.update_export_summary()
        self.run_backend([META_PY,'--odb',odb,'--json',META_JSON],self.log,done,'Reading metadata')

    def refresh_sets(self):
        if not self.meta or not self.instance_cb.get():return
        info=self.meta['instances'][self.instance_cb.get()]
        vals=[WHOLE]
        if int(info.get('grain_set_count',0))>0:vals.append(ALL_GRAINS)
        vals+=info.get('element_sets',[])
        self.set_cb['values']=vals
        if vals:self.set_cb.current(0)

    def frame_count(self,step): return int(self.meta['steps'][step]['nframes']) if self.meta and step else 0
    def populate_frames(self):
        n=self.frame_count(self.step_cb.get()); vals=[str(i) for i in range(n)]; self.frame_cb['values']=vals
        if vals:self.frame_cb.current(len(vals)-1)
    def populate_ref_frames(self):
        n=self.frame_count(self.ref_step_cb.get()); vals=[str(i) for i in range(n)]; self.ref_frame_cb['values']=vals
        if vals:self.ref_frame_cb.current(0)
    def selected_series_steps(self): return [self.series_steps.get(i) for i in self.series_steps.curselection()]
    def populate_common_frames(self):
        ss=self.selected_series_steps(); self.common_frames.delete(0,'end')
        if not ss or not self.meta:return
        n=min(self.frame_count(s) for s in ss)
        for i in range(n):self.common_frames.insert('end',str(i))
    def add_series_frames(self,all_frames):
        ss=self.selected_series_steps()
        frames=[int(self.common_frames.get(i)) for i in (range(self.common_frames.size()) if all_frames else self.common_frames.curselection())]
        for s in ss:
            for f in frames:
                if (s,f) not in self.selected_states:self.selected_states.append((s,f))
        self.selected_states.sort(key=lambda x:(list(self.meta['steps']).index(x[0]),x[1])); self.refresh_states_list()
    def refresh_states_list(self):
        self.states_list.delete(0,'end')
        for s,f in self.selected_states:self.states_list.insert('end','%s | %d'%(s,f))
        self.update_export_summary()

    def update_export_summary(self):
        if not hasattr(self,'summary'): return
        lines=[]
        odb=self.odb_var.get().strip()
        lines.append('ODB      : %s' % (odb or '<not selected>'))
        lines.append('Instance : %s' % (self.instance_cb.get() or '<not selected>'))
        lines.append('Region   : %s' % (self.set_cb.get() or WHOLE))
        if self.series_var.get():
            lines.append('Mode     : PVD time series')
            lines.append('States   : %d selected' % len(self.selected_states))
            for s,f in self.selected_states:
                lines.append('  %s / Frame %d' % (s,f))
        else:
            lines.append('Mode     : Single VTU')
            lines.append('State    : %s / Frame %s' % (self.step_cb.get() or '<none>', self.frame_cb.get() or '<none>'))
        try:
            fs=self.selected_fields()
        except Exception:
            fs=[]
        lines.append('Fields   : %s' % (', '.join(fs) if fs else '<none>'))
        derived=[]
        if self.mises_var.get(): derived.append('Mises')
        if self.ipf_var.get(): derived.append('Initial IPF (%s)' % self.ipf_dir.get())
        if self.gnd_diff_var.get():
            _gcb=getattr(self,'gnd_mode_cb',None)
            derived.append('GND DAT difference (18 slips + 9 directions)'
                           if (_gcb is not None and _gcb.current()==1)
                           else 'GND DAT difference (18 slips)')
        if self.gnd_slide_diff_var.get(): derived.append('GND sliding-reference difference (18 slips)')
        if self.delta_var.get():
            derived.append('Difference %s ; ref=%s / Frame %s' % (
                self.delta_field.get() or '<field>',
                self.ref_step_cb.get() or '<step>',
                self.ref_frame_cb.get() or '<frame>'))
        lines.append('Derived  : %s' % (', '.join(derived) if derived else '<none>'))
        lines.append('Frame policy : %s' % self.frame_policy_var.get())
        lines.append('Field policy : %s' % self.field_policy_var.get())
        lines.append('Compatibility : %s' % self.compatibility_mode_var.get())
        lines.append('Write mode    : %s' % ('in_place' if self.write_mode_var.get() else 'safe_copy'))
        if self.cleanup_removed_var.get():
            lines.append('Cleanup      : delete VTU files removed by frame sync')
        if self.bbox_var.get().strip(): lines.append('BBox     : %s' % self.bbox_var.get().strip())
        lines.append('Output   : %s' % (self.output_file.get().strip() or '<not set>'))
        self.summary.configure(state='normal')
        self.summary.delete('1.0','end')
        self.summary.insert('end','\n'.join(lines))
        self.summary.configure(state='disabled')
    def remove_states(self):
        inds=list(self.states_list.curselection())
        for i in reversed(inds): self.selected_states.pop(i)
        self.refresh_states_list()
    def clear_states(self): self.selected_states=[]; self.refresh_states_list()

    def read_fields(self):
        if not self.step_cb.get() or not self.frame_cb.get():return
        args=[FIELDS_PY,'--odb',self.odb_var.get(),'--step',self.step_cb.get(),'--frame',self.frame_cb.get(),'--json',FIELDS_JSON]
        def done(rc):
            if rc!=0 or not FIELDS_JSON.exists():return
            self.field_meta=json.loads(FIELDS_JSON.read_text())
            self.fields_lb.delete(0,'end'); delta=[]
            for f in self.field_meta['fields']:
                self.fields_lb.insert('end',f['name']); delta.append(f['name'])
                if f['name'] in ('SDV29','SDV78'):self.fields_lb.selection_set('end')
            self.delta_field_cb['values']=delta
            if delta:self.delta_field_cb.current(0)
            self.update_export_summary()
        self.run_backend(args,self.log,done,'Reading fields')

    def selected_fields(self): return [self.fields_lb.get(i) for i in self.fields_lb.curselection()]
    def run_export(self):
        if not self.meta or not self.instance_cb.get():messagebox.showerror('Export','先读取元数据');return
        fs=self.selected_fields()
        if not fs and not self.mises_var.get() and not self.ipf_var.get() and not self.delta_var.get() and not self.gnd_diff_var.get() and not self.gnd_slide_diff_var.get():messagebox.showerror('Export','请选择场变量或派生场');return
        if self.ipf_var.get() and not Path(self.inp_var.get()).exists():messagebox.showerror('IPF','Initial IPF需要有效INP');return
        if self.gnd_diff_var.get() and not Path(self.gnd_dat_var.get()).exists():messagebox.showerror('GND','GND差值需要有效的 gnd_field.dat');return
        field_policy='sync' if self.field_policy_cb.current() == 1 else 'merge'
        frame_policy='sync' if self.frame_policy_cb.current() == 1 else 'merge'
        write_mode='in_place' if self.write_mode_var.get() else 'safe_copy'
        if write_mode == 'in_place':
            if not self.series_var.get():
                messagebox.showerror('In-place update',
                                     self._m('原位更新只适用于已有 PVD 时间序列；请先勾选“PVD时间序列”。',
                                             'In-place update applies only to an existing PVD time series.'))
                return
            output_path = Path(self.output_file.get())
            if not output_path.is_file():
                messagebox.showerror('In-place update',
                                     self._m('原位更新必须选择一个已经存在的 PVD；首次导出请取消此选项。',
                                             'In-place update requires an existing PVD; uncheck it for first export.'))
                return
            if frame_policy != 'merge' or field_policy != 'merge' or self.cleanup_removed_var.get():
                messagebox.showerror('In-place update',
                                     self._m('原位更新只允许 Frame Merge + Field Merge，且不能删除 VTU。',
                                             'In-place update requires Frame Merge + Field Merge with file deletion disabled.'))
                return
        # Require informed confirmation before any Sync operation.
        if self.series_var.get() and frame_policy == 'sync':
            if not messagebox.askyesno('确认 Frame Sync',
                    'Frame Sync 将从 PVD 时间序列中移除所有未选的旧帧。\n'
                    '只补充 SDV 时，应选择 Frame Merge。是否继续？', icon='warning'):
                return
        if field_policy == 'sync':
            if not messagebox.askyesno('确认 Field Sync',
                    'Field Sync 会从选中帧中删除本次未选择的已有 SDV、GND 和 IPF 字段。\n'
                    '只补充 SDV 时，应选择 Field Merge。是否继续？', icon='warning'):
                return
        if self.series_var.get() and self.cleanup_removed_var.get():
            if not messagebox.askyesno('确认永久删除文件',
                    '危险：此选项会物理删除不在 Frame Sync 选择中的 VTU 文件。\n'
                    '删除无法通过 PVD 恢复。是否确认？', icon='warning'):
                return
        common=['--odb',self.odb_var.get(),'--instance',self.instance_cb.get(),'--fields',','.join(fs),
                '--field-policy',field_policy,
                '--confirm-field-sync', '1' if field_policy == 'sync' else '0']
        sv=self.set_cb.get()
        if sv and sv!=WHOLE: common += ['--element-set','__ALL_GRAINS__' if sv==ALL_GRAINS else sv]
        if self.bbox_var.get().strip():common += ['--bbox',self.bbox_var.get().strip()]
        if self.delta_var.get() and self.delta_field.get() and self.ref_step_cb.get() and self.ref_frame_cb.get(): common += ['--delta-field',self.delta_field.get(),'--ref-step',self.ref_step_cb.get(),'--ref-frame',self.ref_frame_cb.get()]
        if self.mises_var.get():common += ['--mises','1']
        if self.ipf_var.get():common += ['--initial-ipf','1','--inp',self.inp_var.get(),'--ipf-dir',self.ipf_dir.get()]
        if self.gnd_diff_var.get():
            # Linux-only extension: index 1 = 18 slips + 9 Burgers directions.
            gm='all' if self.gnd_mode_cb.current()==1 else 'slips'
            common += ['--gnd-diff','1','--gnd-dat',self.gnd_dat_var.get(),'--gnd-diff-mode',gm]
        if self.gnd_slide_diff_var.get():
            sr='previous_last' if self.gnd_slide_ref_cb.current() == 1 else 'sliding0'
            common += ['--gnd-slide-diff','1','--gnd-slide-ref',sr]
        if self.series_var.get():
            if not self.selected_states:messagebox.showerror('Series','请添加Step/Frame状态');return
            compatibility_mode = ('standard', 'fast', 'strict')[max(0, self.compatibility_mode_cb.current())]
            adoption=[]
            output = Path(self.output_file.get())
            effective_output=output
            target_manifest = output.parent / (output.stem+'_frames') / '_ODB2VTUS_manifest.json'
            missing_manifest = output.is_file() and not target_manifest.is_file()
            if write_mode == 'in_place':
                if compatibility_mode == 'standard' and missing_manifest:
                    messagebox.showerror(
                        'In-place compatibility',
                        self._m('当前数据没有可信 Manifest。原位更新请选择“快速兼容”或“严格验证”；标准模式不能直接接管无 Manifest 数据。',
                                'This dataset has no trusted Manifest. For in-place update choose Fast or Strict compatibility; Standard mode cannot adopt a manifest-less dataset directly.'))
                    return
                if not messagebox.askyesno(
                        '原位增量更新 / In-place update',
                        self._m(
                            '将直接更新已有 VTU，原文件名和 PVD 路径不变，不创建 MIGRATED_SAFE 文件夹。每帧先写入同目录临时文件，成功后原子替换；异常中断时保留回滚硬链接和事务日志。请确认已有独立备份。继续？',
                            'Existing VTUs will be updated at their original paths. No MIGRATED_SAFE folder will be created. Each frame is written to an adjacent temporary file and atomically replaces the original after success; rollback hardlinks and a transaction journal protect interrupted updates. Ensure you have an independent backup. Continue?'),
                        icon='warning'):
                    return
            if missing_manifest and compatibility_mode == 'standard':
                title = self._m('需要原始 Manifest','Original Manifest required')
                messagebox.showinfo(title, self._m(
                    '标准模式需要可信 Manifest。如早期版本从未生成过，请取消并选择快速兼容模式。',
                    'Standard mode requires a trusted Manifest. Choose Fast compatibility if no original Manifest exists.'))
                selected = filedialog.askopenfilename(title=title, filetypes=[('Manifest JSON','*.json')])
                if not selected:return
                adoption=['--adopt-manifest-path',selected]
            if missing_manifest and compatibility_mode != 'standard' and write_mode == 'safe_copy':
                effective_output = output.parent / (output.stem + '_MIGRATED_SAFE') / output.name
                if frame_policy != 'merge' or field_policy != 'merge' or self.cleanup_removed_var.get():
                    messagebox.showerror('Compatibility','旧版安全迁移只允许 Frame Merge + Field Merge 且不允许删除文件。')
                    return
                if not messagebox.askyesno('Legacy compatibility',self._m(
                        '无 Manifest 的旧数据将先校验并完整复制到新的 MIGRATED_SAFE 文件夹，然后仅在新目录追加字段。原数据不改变。继续？',
                        'Legacy data without Manifest will be checked and independently copied to a NEW MIGRATED_SAFE folder before increment. Original files stay unchanged. Continue?'), icon='warning'):
                    return
            SERIES_FILE.write_text('\n'.join('%s\t%d'%x for x in self.selected_states)+'\n',encoding='utf-8-sig')
            args=[SERIES_PY]+common+[
                '--selection-file',SERIES_FILE,'--out-pvd',self.output_file.get(),
                '--frame-policy',frame_policy, '--compatibility-mode',compatibility_mode,
                '--cleanup-removed-frames','1' if self.cleanup_removed_var.get() else '0',
                '--confirm-frame-sync', '1' if frame_policy == 'sync' else '0',
                '--confirm-delete-files', '1' if self.cleanup_removed_var.get() else '0',
                '--write-mode', write_mode] + adoption
        else:
            if not self.step_cb.get() or not self.frame_cb.get():return
            args=[EXPORT_PY]+common+['--step',self.step_cb.get(),'--frame',self.frame_cb.get(),'--out',self.output_file.get()]
        self.update_export_summary()
        def done(rc):
            if rc==0:
                self.log.insert('end','\n[GUI] EXPORT COMPLETE\n')
                self.log.insert('end','Output: %s\n' % effective_output)
                self.log.see('end')
                messagebox.showinfo(
                    '导出完成 / Export Complete',
                    'ODB2VTU-S 导出完成。\n\n输出文件：\n%s' % effective_output
                )
            else:
                self.log.insert('end','\n[GUI] EXPORT FAILED (return code %s)\n' % rc)
                self.log.see('end')
                messagebox.showerror(
                    '导出失败 / Export Failed',
                    'ODB2VTU-S 导出未正常完成。\n返回码：%s\n\n请查看“输出信息 / Output Messages”。' % rc
                )
        self.run_backend(args,self.log,done,'Exporting')

    # ---------------- Curve logic ----------------
    def curve_browse_odb(self):
        p=filedialog.askopenfilename(filetypes=[('Abaqus ODB','*.odb')]);
        if p:self.curve_odb.set(p); self.curve_update_out()
    def curve_dir(self):
        p=self.curve_odb.get() or self.odb_var.get();
        if not p:return ''
        d=Path(p).parent/'ODB2VTU_Output';d.mkdir(exist_ok=True);return str(d)
    def curve_update_out(self):
        p=self.curve_odb.get() or self.odb_var.get();
        if not p:return
        d=self.curve_dir() if self.curve_auto.get() or not getattr(self,'curve_custom_dir','') else self.curve_custom_dir
        self.curve_out.set(str(Path(d)/(Path(p).stem+'_curve.csv')))
    def curve_choose_folder(self):
        d=filedialog.askdirectory();
        if d:self.curve_custom_dir=d;self.curve_auto.set(False);self.curve_update_out()
    def curve_choose_file(self):
        p=filedialog.asksaveasfilename(defaultextension='.csv',filetypes=[('CSV','*.csv')]);
        if p:self.curve_out.set(p);self.curve_auto.set(False);self.curve_custom_dir=str(Path(p).parent)
    def curve_read_meta(self):
        odb=self.curve_odb.get() or self.odb_var.get();
        if not Path(odb).exists():messagebox.showerror('Curve','选择ODB');return
        self.curve_odb.set(odb); self.curve_update_out()
        def done(rc):
            if rc!=0 or not CURVE_META_JSON.exists():return
            self.curve_meta=json.loads(CURVE_META_JSON.read_text()); self.curve_steps.delete(0,'end')
            for s in self.curve_meta['steps']:self.curve_steps.insert('end',s)
            if self.curve_steps.size():self.curve_steps.selection_set(0);self.curve_refresh_regions()
        self.run_backend([CURVE_META_PY,'--odb',odb,'--json',CURVE_META_JSON],self.curve_log,done,'History metadata')
    def curve_selected_steps(self):return [self.curve_steps.get(i) for i in self.curve_steps.curselection()]
    def curve_refresh_regions(self):
        ss=self.curve_selected_steps();
        if not self.curve_meta or not ss:self.curve_region['values']=[];return
        sets=[set(self.curve_meta['steps'][s]['regions']) for s in ss]; common=sorted(set.intersection(*sets)) if sets else []
        self.curve_region['values']=common
        if common:self.curve_region.current(0);self.curve_refresh_vars()
    def curve_find_node(self):
        needle=self.curve_node.get().strip();
        if not needle or not self.curve_meta:return
        ss=self.curve_selected_steps();
        if not ss:return
        for r,info in self.curve_meta['steps'][ss[0]]['regions'].items():
            if str(info.get('node_label',''))==needle and r in self.curve_region['values']:
                self.curve_region.set(r);self.curve_refresh_vars();return
        messagebox.showinfo('Node','当前共同History Regions中未找到该节点。')
    def curve_refresh_vars(self):
        ss=self.curve_selected_steps(); r=self.curve_region.get();
        if not self.curve_meta or not ss or not r:return
        varsets=[set(self.curve_meta['steps'][s]['regions'][r]['variables']) for s in ss]
        common=sorted(set.intersection(*varsets)) if varsets else []
        vals=['StepTime','GlobalTime']+common
        if 'RF1' in common and 'CF2' in common: vals.append(COF)
        self.curve_x['values']=vals;self.curve_y['values']=vals
        if vals:self.curve_x.current(0);self.curve_y.current(min(1,len(vals)-1))
        self.curve_apply_preset()
    def curve_apply_preset(self):
        p=self.curve_preset.get(); mp={'RF1-U1':('U1','RF1'),'CF2-U2':('U2','CF2'),'RF2-U2':('U2','RF2'),'COF-Time':('GlobalTime',COF),'COF-U1':('U1',COF),'U2-Time':('GlobalTime','U2')}
        if p in mp:
            x,y=mp[p]; vals=list(self.curve_x['values'])
            if x in vals:self.curve_x.set(x)
            if y in vals:self.curve_y.set(y)
            self.x_abs.set(False);self.y_abs.set(p=='CF2-U2')
    def curve_export(self):
        ss=self.curve_selected_steps(); r=self.curve_region.get(); x=self.curve_x.get(); y=self.curve_y.get()
        if not ss or not r or not x or not y:return
        CURVE_STEPS_FILE.write_text('\n'.join(ss)+'\n',encoding='utf-8-sig')
        try: xs=float(self.x_scale.get());ys=float(self.y_scale.get());xo=float(self.x_off.get());yo=float(self.y_off.get())
        except ValueError:messagebox.showerror('Curve','Scale/offset必须为数字');return
        args=[CURVE_EXPORT_PY,'--odb',self.curve_odb.get(),'--steps-file',CURVE_STEPS_FILE,'--region',r,'--xsource',x,'--ysource',y,'--out',self.curve_out.get(),'--x-abs',int(self.x_abs.get()),'--y-abs',int(self.y_abs.get()),'--x-scale',xs,'--y-scale',ys,'--x-offset',xo,'--y-offset',yo,'--dedupe-boundary',int(self.dedupe.get())]
        def done(rc):
            if rc==0:
                messagebox.showinfo('Curve export complete','CSV 导出完成。\n\n%s' % self.curve_out.get())
            else:
                messagebox.showerror('Curve export failed','CSV 导出失败，返回码：%s\n请查看日志。' % rc)
        self.run_backend(args,self.curve_log,done,'Curve export')

    # ---------------- Analysis logic ----------------
    def analysis_default_out(self):
        odb=self.odb_var.get();
        if odb:self.a_out.set(str(Path(odb).parent/'ODB2VTU_Output'/'Field_Analysis'))
    def analysis_frames(self):
        if not self.meta or not self.a_step.get():return
        vals=[str(i) for i in range(self.frame_count(self.a_step.get()))];self.a_frame['values']=vals
        if vals:self.a_frame.current(len(vals)-1)
    def analysis_choose_out(self):
        d=filedialog.askdirectory();
        if d:self.a_out.set(d)
    def analysis_read_fields(self):
        if not self.a_step.get() or not self.a_frame.get():return
        tmp=WORK_DIR/'analysis_fields.json'
        def done(rc):
            if rc!=0 or not tmp.exists():return
            j=json.loads(tmp.read_text()); vals=[]; has_s=False
            for f in j['fields']:
                name=f['name']; comps=f.get('components') or []
                if name=='S':has_s=True
                if comps: vals.extend(str(c) for c in comps)
                else: vals.append(name)
            vals=sorted(set(vals))
            if has_s:vals.insert(0,'Mises')
            self.a_field['values']=vals
            if vals:self.a_field.current(0)
        self.run_backend([FIELDS_PY,'--odb',self.odb_var.get(),'--step',self.a_step.get(),'--frame',self.a_frame.get(),'--json',tmp],self.analysis_log,done,'Analysis variables')
    def analysis_run(self):
        if not self.a_field.get():messagebox.showerror('Analysis','先读取并选择变量');return
        Path(self.a_out.get()).mkdir(parents=True,exist_ok=True)
        args=[ANALYSIS_PY,'--odb',self.odb_var.get(),'--instance',self.a_instance.get(),'--step',self.a_step.get(),'--frame',self.a_frame.get(),'--field-token',self.a_field.get(),'--top-n',self.a_top.get(),'--rank-stat',self.a_rank.get(),'--direction',self.a_dir.get(),'--band-percent',self.a_band.get(),'--outdir',self.a_out.get(),'--export-vtu',int(self.a_export_vtu.get()),'--vtu-scope',self.a_scope.get(),'--split-grains',int(self.a_split.get())]
        if self.a_bbox.get().strip():args += ['--bbox',self.a_bbox.get().strip()]
        def done(rc):
            if rc==0:
                messagebox.showinfo('Field analysis complete','场变量分析完成。\n\n输出目录：\n%s' % self.a_out.get())
            else:
                messagebox.showerror('Field analysis failed','场变量分析失败，返回码：%s\n请查看日志。' % rc)
        self.run_backend(args,self.analysis_log,done,'Field analysis')

    def open_folder(self,p):
        try:
            p=str(p)
            if not p:return
            subprocess.Popen(['xdg-open',p])
        except Exception as exc:messagebox.showerror('Open Folder',str(exc))

if __name__=='__main__':
    try:
        App().mainloop()
    except tk.TclError as exc:
        sys.stderr.write('GUI startup failed: %s\n' % exc)
        sys.stderr.write('On a headless Linux node, use X11 forwarding/VNC or run the backend CLI scripts directly.\n')
        sys.exit(2)

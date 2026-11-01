// Run production methods with GI boundaries replaced; no Shell session required.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const root = process.argv[2];
function load(file, expression, globals = {}) {
    const source = fs.readFileSync(path.join(root, file), 'utf8')
        .replace(/^import\s[\s\S]*?;\s*$/gm, '')
        .replace(/export default class /g, 'class ')
        .replace(/export /g, '');
    return vm.runInNewContext(source + '\n' + expression, globals);
}
let failures = 0;
function test(name, fn) {
    try { fn(); console.log('PASS', name); }
    catch (error) { failures++; console.error('FAIL', name, error.message); }
}

const FrameType = { NORMAL: 0, DIALOG: 1, MODAL_DIALOG: 2, UTILITY: 3, MENU: 4, ATTACHED: 5 };
const WindowRules = load('src/components/applications/window_rules.js', 'WindowRules',
    { Meta: { FrameType } });

function win(wm_class, { app_id = null, parent = null, frame = FrameType.NORMAL, title = null } = {}) {
    return {
        get_wm_class: () => wm_class,
        get_title: () => title,
        get_gtk_application_id: () => app_id,
        get_transient_for: () => parent,
        get_frame_type: () => frame,
    };
}
function rules(enable_all, whitelist, blacklist) {
    return new WindowRules({ applications: {
        ENABLE_ALL: enable_all, WHITELIST: whitelist, BLACKLIST: blacklist,
    } });
}

test('an attached dialog inherits its app through transient-for', () => {
    const app = win('org.gnome.TextEditor');
    const dialog = win('xdg-desktop-portal-gnome', { parent: app, frame: FrameType.ATTACHED });
    assert.equal(rules(false, ['org.gnome.TextEditor'], []).matches(dialog), true);
});

test('a utility palette is blurred like its app', () => {
    const app = win('gimp');
    const palette = win('gimp', { parent: app, frame: FrameType.UTILITY });
    assert.equal(rules(true, [], []).matches(palette), true);
});

test('the GTK application id matches when the wm_class does not', () => {
    const window = win('', { app_id: 'org.gnome.Nautilus' });
    assert.equal(rules(false, ['org.gnome.Nautilus'], []).matches(window), true);
});

test('the allow list wins over the block list in all mode', () => {
    const window = win('io.github.DevWebeloper.AuraGlassSettings');
    assert.equal(rules(true, ['io.github.DevWebeloper.AuraGlassSettings'], ['*aura*']).matches(window), true);
});

test('a blocked app stays unblurred, dialogs included', () => {
    const app = win('firefox');
    const dialog = win('firefox', { parent: app, frame: FrameType.ATTACHED });
    assert.equal(rules(true, [], ['*firefox*']).matches(dialog), false);
});

test('a title rule matches the title, not the class', () => {
    const pip = win('firefox', { title: 'Picture-in-Picture' });
    const browser = win('firefox', { title: 'Picture-in-Picture docs' });
    assert.equal(rules(false, ['title:picture-in-picture'], []).matches(pip), true);
    assert.equal(rules(false, ['title:picture-in-picture'], []).matches(browser), false);
    assert.equal(rules(false, ['title:firefox'], []).matches(pip), false);
    assert.equal(rules(false, ['Picture-in-Picture'], []).matches(pip), false);
});

test('a title rule follows the transient-for chain like a class rule', () => {
    const app = win('firefox', { title: 'Docs - Mozilla Firefox' });
    const middle = win('firefox', { parent: app, frame: FrameType.DIALOG, title: 'Preferences' });
    const dialog = win('xdg-desktop-portal-gnome', { parent: middle, frame: FrameType.ATTACHED, title: 'Save As' });
    assert.equal(rules(false, ['title:*Mozilla Firefox'], []).matches(dialog), true);
    assert.equal(rules(true, [], ['title:*Mozilla Firefox']).matches(dialog), false);
    assert.equal(rules(false, ['title:Save As'], []).matches(dialog), true);
    assert.equal(rules(false, ['title:Save As'], []).matches(app), false);
});

test('class rules still reach the chain and the application id beside title rules', () => {
    const app = win('', { app_id: 'org.gnome.Nautilus', title: 'Home' });
    const dialog = win('xdg-desktop-portal-gnome', { parent: app, frame: FrameType.ATTACHED, title: 'Save As' });
    assert.equal(rules(false, ['title:Nothing', 'org.gnome.Nautilus'], []).matches(dialog), true);
});

test('the allow list wins over a title on the block list in all mode', () => {
    const window = win('firefox', { title: 'Picture-in-Picture' });
    assert.equal(rules(true, ['firefox'], ['title:Picture-in-Picture']).matches(window), true);
    assert.equal(rules(true, [], ['title:Picture-in-Picture']).matches(window), false);
});

test('a window with no class anywhere is not blurred, whatever its title', () => {
    assert.equal(rules(false, ['title:Save As'], []).matches(win('', { title: 'Save As' })), false);
});

test('menus are never blurred', () => {
    assert.equal(rules(true, [], []).matches(win('org.gnome.Nautilus', { frame: FrameType.MENU })), false);
});

test('a transient-for loop ends', () => {
    const a = win('a'), b = win('b', { parent: a });
    a.get_transient_for = () => b;
    assert.equal(rules(false, ['b'], []).matches(a), true);
});

// full-size-buffers: the stock rules, then the kept-at-monitor-size ones.
const sizing = load('src/render/shader/texture_region.js',
    '({ set_full_size_buffers, textureFits, initialTextureCapacity, getTextureCapacity })');

test('stock sizing is exact, grows 1.25x, stops at the view and shrinks below half', () => {
    sizing.set_full_size_buffers(false);
    assert.equal(sizing.initialTextureCapacity(200, 3440), 200);
    assert.equal(sizing.getTextureCapacity(400, 300, 3440), 500);
});

test('full-size buffers start at the monitor and never shrink', () => {
    sizing.set_full_size_buffers(true);
    assert.equal(sizing.initialTextureCapacity(200, 3440), 3440);
    assert.equal(sizing.getTextureCapacity(400, 300, 3440), 3440);
    assert.equal(sizing.textureFits({}, 1, 1, 3440, 1440), true);
    assert.equal(sizing.textureFits({}, 3441, 1, 3440, 1440), false);
    assert.equal(sizing.initialTextureCapacity(4000, 3440), 4000);
    sizing.set_full_size_buffers(false);
});

// static-maximized: the real ApplicationsBlur, WindowOpacity and geometry over fake actors.
const Connections = load('src/conveniences/connections.js', 'Connections', { GObject: {} });
const WindowOpacity = load('src/components/applications/window_opacity.js', 'WindowOpacity',
    { Clutter: { AnimationMode: {} } });
const BLUR_ACTOR_NAME = 'bms-application-blurred-widget';

class Signals {
    constructor() { this.handlers = new Map(); this.next_id = 1; }
    connect(signal, fn) {
        this.handlers.set(this.next_id, { signal, fn });
        return this.next_id++;
    }
    disconnect(id) { this.handlers.delete(id); }
    // as GObject does: a handler disconnected during the emission does not run, nor does a new one
    emit(signal, ...args) {
        [...this.handlers].forEach(([id, handler]) => {
            if (handler.signal === signal && this.handlers.has(id))
                handler.fn(this, ...args);
        });
    }
}

class FakeActor extends Signals {
    constructor(name = '') {
        super();
        Object.assign(this, {
            name, opacity: 255, visible: true, children: [], transitions: new Map(), parent: null,
            scale_x: 1, scale_y: 1, translation_x: 0, translation_y: 0, width: 800, height: 600,
            pivot_point: { x: 0, y: 0 }, below: null, clip: null,
        });
    }
    get mapped() { return this.visible; }
    show() { this.visible = true; }
    hide() { this.visible = false; }
    get_children() { return [...this.children]; }
    insert_child_at_index(child, index) {
        this.children.splice(index, 0, child);
        child.parent = this;
        this.emit('child-added', child);
    }
    set_child_below_sibling(child) { this.below = child; }
    set_scale() {}
    set_clip(...clip) { this.clip = clip; }
    get_transition(name) { return this.transitions.get(name) ?? null; }
    ease({ opacity, onStopped }) {
        this.remove_transition('opacity');
        this.transitions.set('opacity', { target: opacity, onStopped });
    }
    remove_transition(name) {
        const transition = this.transitions.get(name);
        this.transitions.delete(name);
        transition?.onStopped?.(false);
    }
    finish_fade() {
        const transition = this.transitions.get('opacity');
        assert.ok(transition, `${this.name || 'content'} has no fade to finish`);
        this.transitions.delete('opacity');
        this.opacity = transition.target;
        transition.onStopped?.(true);
    }
    destroy() {
        this.remove_transition('opacity');
        this.destroyed = true;
        if (this.parent) {
            this.parent.children.splice(this.parent.children.indexOf(this), 1);
            this.parent.emit('child-removed', this);
        }
    }
}

const WORK_AREA = { x: 0, y: 32, width: 1920, height: 1048 };
const SMALL = { x: 100, y: 100, width: 800, height: 600 };

class FakeWindow extends Signals {
    constructor(actor) {
        super();
        Object.assign(this, {
            actor, frame: SMALL, monitor: 0, client: 0, area: WORK_AREA, area_reads: 0,
            maximized_horizontally: false, maximized_vertically: false, fullscreen: false,
        });
    }
    get_compositor_private() { return this.actor; }
    get_frame_rect() { return this.frame; }
    get_buffer_rect() { return this.frame; }
    get_monitor() { return this.monitor; }
    get_work_area_current_monitor() { this.area_reads++; return this.area; }
    get_client_type() { return this.client; }
    showing_on_its_workspace() { return true; }
    get_wm_class() { return 'Editor'; }
    get_title() { return 'Untitled'; }
    get_gtk_application_id() { return null; }
    get_transient_for() { return null; }
    get_frame_type() { return FrameType.NORMAL; }
    set_maximized(maximized) {
        this.maximized_horizontally = this.maximized_vertically = maximized;
        this.emit('notify::maximized-horizontally');
        this.emit('notify::maximized-vertically');
    }
    set_fullscreen(fullscreen) {
        this.fullscreen = fullscreen;
        this.emit('notify::fullscreen');
    }
    set_frame(frame) {
        this.frame = frame;
        this.emit('size-changed');
    }
}

function fixture({ static_blur = false, blur_on_overview = false } = {}) {
    const counts = { static: 0, dynamic: 0, destroyed: 0 };
    class Pipeline {
        constructor() { counts.static++; }
        create_background_with_effects(monitor, managers, parent, name) {
            const actor = new FakeActor(name);
            parent.insert_child_at_index(actor, 0);
            managers.push({
                backgroundActor: { monitor }, _bms_pipeline: this, destroy() {},
            });
            return actor;
        }
        destroy() { counts.destroyed++; }
    }
    class DynamicPipeline {
        constructor() { counts.dynamic++; }
        create_background_with_effect(parent, name) {
            const actor = new FakeActor(name);
            parent.insert_child_at_index(actor, 0);
            return [actor, { backgroundActor: actor, _bms_pipeline: this, destroy() {} }];
        }
        repaint_effect() {}
        set_corner_radius() {}
        set_straight_corners() {}
        destroy() { counts.destroyed++; }
    }
    class RoundedPipeline {
        bind() {}
        update() {}
        setStraightCorners() {}
        destroy() {}
    }

    const overview = new Signals();
    const tracker = new Signals();
    const adjustment = new Signals();
    adjustment.value = 0;
    adjustment.settle = null;
    adjustment.get_transition = () => adjustment.settle;
    Object.assign(overview, {
        visible: false, animationInProgress: false, _swipeTracker: tracker,
        _overview: { controls: { _stateAdjustment: adjustment } },
    });
    const monitors = [
        { x: 0, y: 0, width: 1920, height: 1080, geometry_scale: 1 },
        { x: 1920, y: 0, width: 1920, height: 1080, geometry_scale: 1 },
    ];
    const Main = { overview, layoutManager: { monitors } };
    const Meta = { FrameType, WindowClientType: { WAYLAND: 0, X11: 1 } };
    const display = new Signals();
    display.focus_window = null;
    const surface = new FakeActor();
    const actor = new FakeActor();
    actor.insert_child_at_index(surface, 0);
    const window = new FakeWindow(actor);

    const geometry = load('src/components/applications/window_geometry.js',
        '({ compute_scale, covers_monitor, place_dynamic_blur, place_static_blur })',
        { Meta, Main, Config: { PACKAGE_VERSION: '51.0' } });
    const math = Object.create(Math);
    math.clamp = (value, low, high) => Math.min(Math.max(value, low), high);
    const ApplicationsBlur = load('src/components/applications/index.js', 'ApplicationsBlur', {
        ...geometry, Main, Meta, Math: math, console, WindowRules, WindowOpacity, Pipeline,
        DynamicPipeline, RoundedPipeline, BLUR_ACTOR_NAME, BLUR_FADE_IN_TIME: 200,
        finish_preview_fade() {}, is_desktop_window: () => false,
        ApplicationsService: class {},
        Clutter: { AnimationMode: {} },
        Gio: { Settings: class { get_strv() { return []; } } },
        global: {
            display,
            blur_my_shell: {},
            workspace_manager: {
                get_n_workspaces: () => 1,
                get_workspace_by_index: () => ({ list_windows: () => [window] }),
            },
        },
    });
    const applications = {
        ENABLE_ALL: true, WHITELIST: [], BLACKLIST: [], STATIC_BLUR: static_blur, OPACITY: 200,
        CORNER_RADIUS: 30, ROUNDED_CORNERS: 15, CORNER_WHEN_MAXIMIZED: false,
        BLUR_ON_OVERVIEW: blur_on_overview, UNBLUR_WHEN_FULLSCREEN: true, DYNAMIC_OPACITY: false,
        PIPELINE: 'pipeline_default',
    };
    const app = new ApplicationsBlur(new Connections(), { applications, DEBUG: false }, {});
    app.enable();
    const stage = {
        opening() {
            overview.visible = overview.animationInProgress = true;
            overview.emit('showing');
        },
        opened() {
            overview.animationInProgress = false;
            overview.emit('shown');
        },
        closing() {
            overview.animationInProgress = true;
            overview.emit('hiding');
        },
        closed() {
            overview.visible = overview.animationInProgress = false;
            overview.emit('hidden');
        },
    };
    return { app, window, actor, surface, overview, tracker, adjustment, display, counts, stage,
             applications, covers_monitor: geometry.covers_monitor };
}

function assert_settled(window, surface, { blurred }) {
    const blur_actor = window.blur_actor;
    assert.equal(blur_actor.opacity, 255, 'blur opacity');
    assert.equal(blur_actor.visible, blurred, 'blur visibility');
    assert.equal(blur_actor.transitions.size, 0, 'blur still fading');
    assert.equal(surface.opacity, blurred ? 200 : 255, 'content opacity');
    assert.equal(surface.transitions.size, 0, 'content still fading');
}

test('covers_monitor: maximized both ways, fullscreen or over the whole work area', () => {
    const { window, covers_monitor } = fixture();
    const at = (props, frame = SMALL) => {
        Object.assign(window, { maximized_horizontally: false, maximized_vertically: false,
            fullscreen: false, frame }, props);
        return covers_monitor(window);
    };
    assert.equal(at({}), false, 'a small window');
    assert.equal(at({ maximized_horizontally: true }), false, 'maximized one way');
    assert.equal(at({ maximized_vertically: true }), false, 'maximized the other way');
    assert.equal(at({ maximized_horizontally: true, maximized_vertically: true }), true, 'both');
    assert.equal(at({ fullscreen: true }), true, 'fullscreen');
    assert.equal(at({}, WORK_AREA), true, 'Tiling Assistant, sized over the work area');
    assert.equal(at({}, { ...WORK_AREA, width: 960 }), false, 'half tiled');
    assert.equal(at({}, { ...WORK_AREA, height: 524 }), false, 'quarter tiled');
    assert.equal(at({}, { x: -10, y: 0, width: 2000, height: 1200 }), true, 'bigger than the area');
    assert.equal(at({}, { ...WORK_AREA, x: 10 }), false, 'as big, but moved off it');
});

test('covers_monitor: a window on no monitor reads no work area, and is not static', () => {
    const { window, covers_monitor } = fixture();
    window.monitor = -1;
    window.maximized_horizontally = window.maximized_vertically = true;
    const reads = window.area_reads;
    assert.equal(covers_monitor(window), false);
    window.maximized_horizontally = false;
    assert.equal(covers_monitor(window), false);
    assert.equal(window.area_reads, reads);
});

test('static-blur is read in one place only, the type decision', () => {
    const source = fs.readFileSync(path.join(root, 'src/components/applications/index.js'), 'utf8');
    assert.equal(source.match(/STATIC_BLUR/g).length, 1);
    assert.match(source, /wants_static_blur\(meta_window\) \{\s*return this\.settings\.applications\.STATIC_BLUR/);
});

test('a window starts by the type it wants', () => {
    assert.equal(fixture().window.bms_static_blur, false);
    assert.equal(fixture({ static_blur: true }).window.bms_static_blur, true);
});

test('maximizing crosses to static and unmaximizing back, once each', () => {
    const { window, actor, surface, counts } = fixture();
    const first = window.blur_actor;
    const handlers = window.handlers.size;
    const actor_handlers = actor.handlers.size;

    window.maximized_horizontally = true;
    window.emit('notify::maximized-horizontally');
    assert.equal(window.bms_static_blur, false, 'maximized one way is still dynamic');
    assert.equal(window.blur_actor, first);
    window.maximized_vertically = true;
    window.emit('notify::maximized-vertically');
    assert.equal(window.bms_static_blur, true, 'maximized both ways is static');
    assert.equal(first.destroyed, true);
    assert.equal(counts.static, 1);
    window.set_frame(WORK_AREA);
    assert.equal(counts.static, 1, 'the size arriving after the flags is no second crossing');

    // Mutter clears the flags first, and the frame only shrinks when the client has answered
    const static_actor = window.blur_actor;
    window.set_maximized(false);
    assert.equal(window.blur_actor, static_actor, 'still over the work area, so still static');
    window.set_frame(SMALL);
    assert.equal(window.bms_static_blur, false, 'dynamic again once smaller');
    assert.equal(counts.dynamic, 2);
    assert.equal(counts.destroyed, 2, 'each old pipeline is released');
    assert.equal(actor.children.length, 2, 'one blur actor beside the content');
    assert.equal(window.handlers.size, handlers, 'crossings pile up no window handlers');
    assert.equal(actor.handlers.size, actor_handlers, 'nor window actor handlers');
    assert_settled(window, surface, { blurred: true });
});

test('a crossing wires the signals of the new type', () => {
    const { window, actor } = fixture();
    window.frame = SMALL;
    window.emit('position-changed');
    actor.scale_x = 0.5;
    actor.emit('notify::scale-x');
    window.set_maximized(true);
    const static_actor = window.blur_actor;
    assert.ok(static_actor.clip, 'placed as a static blur');
    window.frame = { ...SMALL, x: 200 };
    static_actor.clip = null;
    actor.emit('notify::scale-x');
    assert.ok(static_actor.clip, 'a static blur follows the window actor');
    static_actor.clip = null;
    window.emit('position-changed');
    assert.ok(static_actor.clip, 'and the window position');
    window.set_maximized(false);
    window.set_frame(SMALL);
    assert.equal(window.blur_actor.clip, null, 'a dynamic blur is not clipped from a monitor');
    static_actor.clip = null;
    actor.emit('notify::scale-x');
    assert.equal(window.blur_actor.clip, null);
    assert.equal(static_actor.clip, null, 'the old blur hears nothing');
});

test('being sized over the work area crosses without the flags, and half tiling crosses back', () => {
    const { window, counts } = fixture();
    window.set_frame(WORK_AREA);
    assert.equal(window.bms_static_blur, true);
    window.set_frame({ ...WORK_AREA, width: 960 });
    assert.equal(window.bms_static_blur, false);
    assert.equal(counts.static, 1);
});

test('a move alone can cross, for a window as big as the work area', () => {
    const { window } = fixture();
    window.set_frame({ ...WORK_AREA, x: 40 });
    assert.equal(window.bms_static_blur, false);
    window.frame = WORK_AREA;
    window.emit('position-changed');
    assert.equal(window.bms_static_blur, true);
    window.frame = { ...WORK_AREA, x: 40 };
    window.emit('position-changed');
    assert.equal(window.bms_static_blur, false);
});

test('fullscreen is static with no blur shown, and comes back whole', () => {
    const { window, surface, counts } = fixture();
    window.set_fullscreen(true);
    assert.equal(window.bms_static_blur, true);
    assert_settled(window, surface, { blurred: false });
    window.set_fullscreen(false);
    window.set_frame(SMALL);
    assert.equal(window.bms_static_blur, false);
    assert_settled(window, surface, { blurred: true });
    assert.equal(counts.static, 1);
});

test('nothing rebuilds while the type stays', () => {
    const { window, actor, counts } = fixture();
    const first = window.blur_actor;
    [SMALL, { ...SMALL, width: 900 }, { ...WORK_AREA, width: 960 }].forEach(frame => {
        window.set_frame(frame);
        window.emit('position-changed');
    });
    actor.emit('notify::scale-x');
    window.maximized_horizontally = true;
    window.emit('notify::maximized-horizontally');
    assert.equal(window.blur_actor, first);
    assert.equal(counts.dynamic, 1);
    assert.equal(counts.static, 0);
});

test('static-blur=true keeps every window static, whatever it covers', () => {
    const { window, counts } = fixture({ static_blur: true });
    const first = window.blur_actor;
    window.set_maximized(true);
    window.set_frame(WORK_AREA);
    window.set_maximized(false);
    window.set_frame(SMALL);
    window.set_fullscreen(true);
    window.set_fullscreen(false);
    assert.equal(window.blur_actor, first);
    assert.equal(window.bms_static_blur, true);
    assert.equal(counts.static, 1);
    assert.equal(counts.dynamic, 0);
});

test('switching static-blur rebuilds by the new setting and the window', () => {
    const { app, window, applications } = fixture({ static_blur: true });
    applications.STATIC_BLUR = false;
    app.change_blur_type();
    assert.equal(window.bms_static_blur, false);
    window.set_maximized(true);
    assert.equal(window.bms_static_blur, true);
});

test('an interactive resize waits for its end, however often it crosses', () => {
    const { window, surface, display, counts } = fixture();
    const first = window.blur_actor;
    display.emit('grab-op-begin', window, 8193); // Meta.GrabOp.RESIZING_E
    for (let i = 0; i < 20; i++)
        window.set_frame(i % 2 ? SMALL : WORK_AREA);
    window.set_frame(WORK_AREA);
    assert.equal(window.blur_actor, first, 'no rebuild during the resize');
    assert.equal(counts.dynamic, 1);
    display.emit('grab-op-end', window, 8193);
    assert.equal(window.bms_static_blur, true, 'the crossing lands at the end');
    assert.equal(counts.static, 1);
    assert_settled(window, surface, { blurred: true });
});

test('a resize ending where it began does not rebuild', () => {
    const { window, display, counts } = fixture();
    display.emit('grab-op-begin', window, 24577); // Meta.GrabOp.RESIZING_SE
    window.set_frame(WORK_AREA);
    window.set_frame(SMALL);
    display.emit('grab-op-end', window, 24577);
    assert.equal(counts.dynamic, 1);
    assert.equal(counts.static, 0);
});

test('every resizing grab defers, and no moving grab does', () => {
    [36865, 32769, 40961, 8193, 20481, 16385, 24577, 4097, 37121, 8449].forEach(op => {
        const { window, display } = fixture();
        display.emit('grab-op-begin', window, op);
        window.set_frame(WORK_AREA);
        assert.equal(window.bms_static_blur, false, `op ${op}`);
    });
    [1, 1025, 257].forEach(op => {
        const { window, display } = fixture();
        display.emit('grab-op-begin', window, op);
        window.set_frame(WORK_AREA);
        assert.equal(window.bms_static_blur, true, `op ${op}`);
    });
});

test('dragging a maximized window free crosses during the drag', () => {
    const { window, display } = fixture();
    window.set_maximized(true);
    display.emit('grab-op-begin', window, 1); // Meta.GrabOp.MOVING
    window.set_maximized(false);
    window.set_frame(SMALL);
    assert.equal(window.bms_static_blur, false);
});

test("another window's resize does not hold this one back", () => {
    const { window, display } = fixture();
    display.emit('grab-op-begin', new FakeWindow(new FakeActor()), 8193);
    window.set_frame(WORK_AREA);
    assert.equal(window.bms_static_blur, true);
});

test('a window unmanaged during its resize is forgotten', () => {
    const { app, window, display, counts } = fixture();
    display.emit('grab-op-begin', window, 8193);
    window.emit('unmanaging');
    assert.equal(app.resizing_window, null);
    assert.equal(window.blur_actor, undefined);
    assert.equal(window.bms_static_blur, undefined, 'the recorded type goes with the blur');
    display.emit('grab-op-end', window, 8193);
    assert.equal(counts.dynamic, 1);
});

test('entering a monitor decides the type against its work area', () => {
    const { window, display } = fixture();
    window.set_frame(WORK_AREA);
    assert.equal(window.bms_static_blur, true);
    window.monitor = 1;
    window.area = { x: 1920, y: 32, width: 1920, height: 1048 };
    display.emit('window-entered-monitor', 1, window);
    assert.equal(window.bms_static_blur, false, 'the same frame no longer covers it');
    // a window changes monitor after its position does, so its move read the old work area
    window.monitor = 0;
    window.area = WORK_AREA;
    window.frame = { x: 1920, y: 32, width: 1920, height: 1048 };
    window.emit('position-changed');
    assert.equal(window.bms_static_blur, false);
    window.monitor = 1;
    window.area = window.frame;
    display.emit('window-entered-monitor', 1, window);
    assert.equal(window.bms_static_blur, true);
    assert.equal(window.bg_manager.backgroundActor.monitor, 1);
});

test('a static window entering a monitor is remade from its background, a dynamic one is left', () => {
    const { window, display } = fixture();
    window.set_maximized(true);
    const old = window.blur_actor;
    window.monitor = 1;
    display.emit('window-entered-monitor', 1, window);
    assert.notEqual(window.blur_actor, old);
    assert.equal(window.bms_static_blur, true);
    assert.equal(window.bg_manager.backgroundActor.monitor, 1);

    const small = fixture();
    const dynamic = small.window.blur_actor;
    small.window.monitor = 1;
    small.display.emit('window-entered-monitor', 1, small.window);
    assert.equal(small.window.blur_actor, dynamic);
    small.display.emit('window-entered-monitor', 1, new FakeWindow(new FakeActor()));
});

test('the X11 stacking fix follows the type of the blur', () => {
    const { window, actor } = fixture();
    window.client = 1;
    actor.insert_child_at_index(new FakeActor('late'), 0);
    assert.equal(actor.below, null, 'dynamic blur has no such fix');
    window.set_maximized(true);
    actor.insert_child_at_index(new FakeActor('later'), 0);
    assert.equal(actor.below, window.blur_actor, 'static blur is kept at the back');
});

test('removing the blur after crossings restores the content', () => {
    const { app, window, surface, applications } = fixture();
    surface.opacity = 255;
    window.set_maximized(true);
    window.set_frame(WORK_AREA);
    assert.equal(surface.opacity, 200);
    applications.BLACKLIST = ['Editor'];
    app.rules.update();
    app.check_blur(window);
    assert.equal(window.blur_actor, undefined);
    assert.equal(window.bms_static_blur, undefined);
    assert.equal(surface.opacity, 255);
});

test('app to overview: a crossing during the fade waits, and the fade finishes', () => {
    const { window, surface, stage, counts } = fixture();
    const fading = window.blur_actor;
    stage.opening();
    assert.equal(fading.get_transition('opacity').target, 0);
    assert.equal(surface.get_transition('opacity').target, 255);

    window.set_maximized(true);
    window.set_frame(WORK_AREA);
    assert.equal(window.blur_actor, fading, 'the blur fading out is not cut off');
    assert.equal(fading.get_transition('opacity').target, 0);
    assert.equal(surface.get_transition('opacity').target, 255);

    fading.finish_fade();
    surface.finish_fade();
    assert.equal(fading.visible, false);
    stage.opened();
    assert.equal(window.bms_static_blur, true, 'crossed once the overview settled');
    assert.equal(counts.static, 1);
    assert_settled(window, surface, { blurred: false });
});

test('overview to app: the crossed blur fades in with the content, then rests', () => {
    const { window, surface, stage } = fixture();
    stage.opening();
    window.blur_actor.finish_fade();
    surface.finish_fade();
    stage.opened();
    window.set_maximized(true);
    window.set_frame(WORK_AREA);
    assert.equal(window.bms_static_blur, true, 'a settled overview crosses at once');
    assert_settled(window, surface, { blurred: false });

    stage.closing();
    const blur_actor = window.blur_actor;
    assert.equal(blur_actor.visible, true);
    assert.equal(blur_actor.get_transition('opacity').target, 255);
    assert.equal(surface.get_transition('opacity').target, 200);
    blur_actor.finish_fade();
    surface.finish_fade();
    stage.closed();
    assert.equal(window.blur_actor, blur_actor);
    assert_settled(window, surface, { blurred: true });
});

test('overview to app: a crossing during the fade lands whole after it, both ways', () => {
    [true, false].forEach(start_maximized => {
        const { window, surface, stage } = fixture();
        if (start_maximized)
            window.set_maximized(true);
        stage.opening();
        window.blur_actor.finish_fade();
        surface.finish_fade();
        stage.opened();

        stage.closing();
        const fading = window.blur_actor;
        window.set_maximized(!start_maximized);
        window.set_frame(start_maximized ? SMALL : WORK_AREA);
        assert.equal(window.blur_actor, fading, 'the blur fading in is not cut off');
        assert.equal(fading.get_transition('opacity').target, 255);
        assert.equal(surface.get_transition('opacity').target, 200);

        fading.finish_fade();
        surface.finish_fade();
        stage.closed();
        assert.equal(window.bms_static_blur, !start_maximized);
        assert.notEqual(window.blur_actor, fading);
        assert_settled(window, surface, { blurred: true });
    });
});

test('a rebuild forced in the middle of a fade leaves nothing stuck, both ways', () => {
    // a static window changing monitor is rebuilt there and then: it needs that monitor's wallpaper
    const going = fixture({ static_blur: true });
    going.stage.opening();
    const old = going.window.blur_actor;
    going.window.monitor = 1;
    going.display.emit('window-entered-monitor', 1, going.window);
    assert.notEqual(going.window.blur_actor, old);
    assert.equal(going.app.fading_out.has(old), false);
    going.surface.finish_fade();
    assert_settled(going.window, going.surface, { blurred: false });
    going.stage.opened();
    going.stage.closing();
    going.window.blur_actor.finish_fade();
    going.surface.finish_fade();
    going.stage.closed();
    assert_settled(going.window, going.surface, { blurred: true });

    const coming = fixture({ static_blur: true });
    coming.stage.opening();
    coming.window.blur_actor.finish_fade();
    coming.surface.finish_fade();
    coming.stage.opened();
    coming.stage.closing();
    coming.window.monitor = 1;
    coming.display.emit('window-entered-monitor', 1, coming.window);
    assert_settled(coming.window, coming.surface, { blurred: true });
    coming.stage.closed();
    assert_settled(coming.window, coming.surface, { blurred: true });
});

function swipe_to(adjustment, value) {
    adjustment.value = value;
    adjustment.emit('notify::value');
}

test('a swipe: a crossing waits, the blur goes on following, and it lands where it settles', () => {
    const { window, surface, tracker, adjustment, overview } = fixture();
    const followed = window.blur_actor;
    tracker.emit('begin');
    overview.visible = overview.animationInProgress = true;
    overview.emit('showing');
    swipe_to(adjustment, 0.5);
    assert.equal(followed.opacity, 223);
    assert.equal(surface.opacity, 241);

    window.set_maximized(true);
    window.set_frame(WORK_AREA);
    assert.equal(window.blur_actor, followed, 'no rebuild under the fingers');
    swipe_to(adjustment, 0.25);
    assert.equal(followed.opacity, 251);
    assert.equal(surface.opacity, 224);

    // turned back and let go: the overview eases shut
    adjustment.settle = new Signals();
    tracker.emit('end');
    swipe_to(adjustment, 0);
    overview.visible = overview.animationInProgress = false;
    overview.emit('hidden');
    assert.equal(window.blur_actor, followed, 'still following while the ease runs');
    adjustment.settle.emit('stopped', true);
    assert.equal(window.bms_static_blur, true);
    assert_settled(window, surface, { blurred: true });
});

test('a swipe let go open: the crossing lands in the settled overview, with no blur shown', () => {
    const { window, surface, tracker, adjustment, overview } = fixture();
    tracker.emit('begin');
    overview.visible = overview.animationInProgress = true;
    overview.emit('showing');
    swipe_to(adjustment, 0.6);
    window.set_maximized(true);
    adjustment.settle = new Signals();
    tracker.emit('end');
    swipe_to(adjustment, 1);
    adjustment.settle.emit('stopped', true);
    assert.equal(window.bms_static_blur, false, 'the overview is still animating');
    overview.animationInProgress = false;
    overview.emit('shown');
    assert.equal(window.bms_static_blur, true);
    assert_settled(window, surface, { blurred: false });
});

test('a new blur made during a swipe joins it where the swipe has got to', () => {
    const { app, window, surface, tracker, adjustment, overview, applications } = fixture();
    tracker.emit('begin');
    overview.visible = overview.animationInProgress = true;
    swipe_to(adjustment, 0.5);
    applications.BLACKLIST = ['Editor'];
    app.rules.update();
    app.check_blur(window);
    assert.equal(surface.opacity, 255);
    applications.BLACKLIST = [];
    app.rules.update();
    app.check_blur(window);
    assert.equal(window.blur_actor.visible, true, 'not left hidden by the overview being up');
    assert.equal(window.blur_actor.opacity, 223);
    assert.equal(surface.opacity, 241);
});

test('blur-on-overview: the blur stays up across a crossing in the overview', () => {
    const { window, surface, stage } = fixture({ blur_on_overview: true });
    stage.opening();
    window.set_maximized(true);
    stage.opened();
    assert.equal(window.bms_static_blur, true);
    assert_settled(window, surface, { blurred: true });
    stage.closing();
    stage.closed();
    assert_settled(window, surface, { blurred: true });
});

if (failures)
    process.exit(1);

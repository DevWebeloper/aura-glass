// Production application lifecycle; only GI actors/pipelines/timers are simulated.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const root = process.argv[2];
function load(file, expression, globals = {}) {
    const source = fs.readFileSync(`${root}/${file}`, 'utf8')
        .replace(/^import\s[\s\S]*?;\s*$/gm, '').replace(/export default /g, '').replace(/export /g, '');
    return vm.runInNewContext(source + '\n' + expression, globals);
}
const Connections = load('src/conveniences/connections.js', 'Connections', {GObject: {Object: class {}}});
class Actor {
    constructor() { this.handlers = new Map(); this.next = 1; this.children = []; this.visible = true; }
    connect(signal, callback) { const id = this.next++; this.handlers.set(id, {signal, callback}); return id; }
    disconnect(id) { this.handlers.delete(id); }
    emit(signal) { for (const h of [...this.handlers.values()]) if (h.signal === signal) h.callback(); }
    get_children() { return this.children; }
    remove_child(child) { this.children = this.children.filter(c => c !== child); }
    show() { this.visible = true; }
    hide() { this.visible = false; }
    destroy() { this.emit('destroy'); }
    set_child_below_sibling() {}
}
function fixture({staticBlur = false, dynamicOpacity = false} = {}) {
    const actor = new Actor();
    const window = Object.assign(new Actor(), {
        get_compositor_private: () => actor,
        get_wm_class: () => 'Editor', get_gtk_application_id: () => 'Editor',
        get_transient_for: () => null, get_frame_type: () => 0,
        get_client_type: () => 1, get_monitor: () => 0,
        maximized_horizontally: false, maximized_vertically: false, fullscreen: false,
        frame: {x: 100, y: 100, width: 800, height: 600},
        get_frame_rect() { return this.frame; },
        get_work_area_current_monitor: () => ({x: 0, y: 32, width: 1920, height: 1048}),
    });
    const counts = {created: 0, removed: 0, enabled: 0};
    class DummyPipeline {
        constructor() { counts.created++; this.effect = {set_enabled() {}}; this.effects = []; }
        create_background_with_effect(parent) {
            const blur = new Actor(); parent.children.push(blur);
            return [blur, {_bms_pipeline: this, destroy() {}}];
        }
        create_background_with_effects(_monitor, managers, parent) {
            const [blur, manager] = this.create_background_with_effect(parent);
            managers.push(manager); return blur;
        }
        destroy() { counts.removed++; }
    }
    const timers = new Map(); let nextTimer = 1;
    const globals = {
        display: {focus_window: window}, blur_my_shell: {_pipelines_manager: {}},
        workspace_manager: {get_n_workspaces: () => 1, get_workspace_by_index: () => ({list_windows: () => [window]})},
    };
    const Applications = load('src/components/applications.js', 'ApplicationsBlur', {
        Meta: {FrameType: {NORMAL: 0}, WindowClientType: {X11: 1}},
        Main: {overview: {visible: false}}, global: globals,
        PaintSignals: class { disconnect_all_for_actor() {} disconnect_all() {} },
        DummyPipeline, Pipeline: DummyPipeline,
        setTimeout: callback => { const id = nextTimer++; timers.set(id, callback); return id; },
        clearTimeout: id => timers.delete(id),
    });
    const settings = {applications: {
        ENABLE_ALL: true, WHITELIST: [], BLACKLIST: [], STATIC_BLUR: staticBlur,
        DYNAMIC_OPACITY: dynamicOpacity, CORNER_RADIUS: 30, OPACITY: 240,
    }};
    const app = new Applications(new Connections(), settings, null);
    app.update_size = () => {}; // Geometry/rendering is outside this test.
    return {app, actor, window, counts, timers, settings};
}
let failures = 0;
function test(name, run) {
    try { run(); console.log('PASS', name); }
    catch (error) { failures++; console.error('FAIL', name, error.stack); }
}
test('list edits preserve unchanged blur pipelines', () => {
    const {app, window, counts, settings} = fixture();
    app.update_all_windows();
    const originalBlur = window.blur_actor;
    for (let i = 0; i < 20; i++) {
        settings.applications.BLACKLIST = [`OtherApp${i}`];
        app.update_all_windows(false);
    }
    assert.equal(counts.created, 1, 'unaffected windows must not recreate GPU pipelines');
    assert.equal(window.blur_actor, originalBlur);
    settings.applications.BLACKLIST = ['Editor'];
    app.update_all_windows(false);
    assert.equal(window.blur_actor, undefined, 'matching exclusions still remove blur');
    settings.applications.BLACKLIST = [];
    app.update_all_windows(false);
    assert.ok(window.blur_actor, 'removing exclusions restores blur');
    assert.equal(counts.created, 2);
    app.update_all_windows(); // Pipeline selection really does need a rebuild.
    assert.equal(counts.created, 3);
});
test('class-driven blur changes do not accumulate Meta.Window handlers', () => {
    const {app, window, settings} = fixture();
    app.update_all_windows();
    const initial = window.handlers.size;
    for (let i = 0; i < 20; i++) {
        settings.applications.BLACKLIST = ['Editor']; app._update_patterns(); app.check_blur(window);
        settings.applications.BLACKLIST = []; app._update_patterns(); app.check_blur(window);
    }
    assert.equal(window.handlers.size, initial);
});
test('X11 static-blur child listeners are released on disable', () => {
    const {app, actor} = fixture({staticBlur: true});
    for (let i = 0; i < 5; i++) { app.update_all_windows(); app.disable(); }
    assert.equal(actor.handlers.size, 0);
});
test('disable cancels pending blur-type enable', () => {
    const {app, timers, counts} = fixture();
    app.enable = () => { counts.enabled++; };
    app.change_blur_type();
    app.disable();
    for (const callback of timers.values()) callback();
    assert.equal(counts.enabled, 0, 'disabled effects must not reactivate asynchronously');
});
test('rebuild preserves focused-window dynamic opacity', () => {
    const {app, window} = fixture({dynamicOpacity: true});
    app.update_all_windows(); app.set_focus_for_window(window);
    app.update_all_windows();
    assert.equal(app.focused_window_pid, window.bms_pid);
    assert.equal(window.blur_actor.visible, false, 'focused window remains unblurred by the chosen setting');
});
test('whitelist override takes effect immediately in all-apps mode', () => {
    const {app, window, settings} = fixture();
    settings.applications.BLACKLIST = ['Editor'];
    app.update_all_windows();
    assert.equal(window.blur_actor, undefined);
    const callbacks = {};
    settings.applications.BLUR = true;
    const component = (name, values = {}) => new Proxy(values, {get: (target, key) => {
        if (key.endsWith('_changed')) return callback => { callbacks[name + '.' + key] = callback; };
        return target[key];
    }});
    const ShellExtension = load('src/extension.js', 'BlurMyShell', {Extension: class {}});
    const extension = Object.create(ShellExtension.prototype);
    extension._applications_blur = app;
    extension._settings = new Proxy({}, {get: (_target, key) => {
        if (key.endsWith('_changed')) return () => {};
        return component(key, settings[key]);
    }});
    extension._connect_to_settings();
    settings.applications.WHITELIST = ['Editor'];
    callbacks['applications.WHITELIST_changed']();
    assert.ok(window.blur_actor, 'explicit allow overrides blacklist without an unrelated settings change');
    const retained = window.blur_actor;
    settings.applications.WHITELIST = ['Editor', 'Other'];
    callbacks['applications.WHITELIST_changed']();
    assert.equal(window.blur_actor, retained, 'unchanged allow matches retain their GPU pipeline');
    settings.applications.BLACKLIST = ['Editor', 'Another'];
    callbacks['applications.BLACKLIST_changed']();
    assert.equal(window.blur_actor, retained, 'unrelated exclusion changes retain the pipeline');
    settings.applications.ENABLE_ALL = false;
    callbacks['applications.ENABLE_ALL_changed']();
    assert.equal(window.blur_actor, retained, 'unchanged scope matches retain the pipeline');
    settings.applications.WHITELIST = [];
    callbacks['applications.WHITELIST_changed']();
    assert.equal(window.blur_actor, undefined, 'removing override restores the blacklist decision');
});
test('a window that covers its monitor gets static blur, a smaller one dynamic', () => {
    const {app, window, actor, counts} = fixture();
    app.update_all_windows();
    assert.equal(window.bms_static_blur, false, 'a normal window starts dynamic');
    const windowHandlers = window.handlers.size;
    window.maximized_horizontally = true; window.emit('notify::maximized-horizontally');
    assert.equal(window.bms_static_blur, false, 'maximized one way only is not full screen');
    window.maximized_vertically = true; window.emit('notify::maximized-vertically');
    assert.equal(window.bms_static_blur, true, 'maximized both ways turns static');
    assert.equal(counts.created, 2);
    window.maximized_horizontally = window.maximized_vertically = false;
    window.emit('notify::maximized-horizontally'); window.emit('notify::maximized-vertically');
    assert.equal(window.bms_static_blur, false, 'unmaximized turns dynamic again');
    window.fullscreen = true; window.emit('notify::fullscreen');
    assert.equal(window.bms_static_blur, true, 'fullscreen turns static');
    assert.equal(counts.created - counts.removed, 1, 'old pipelines are released on each switch');
    assert.equal(actor.children.length, 1, 'one blur actor stays on the window');
    assert.equal(window.handlers.size, windowHandlers, 'switches add no Meta.Window handlers');
});
test('a window resized over the whole work area is static without maximize flags', () => {
    const {app, window} = fixture();
    app.update_all_windows();
    window.frame = {x: 0, y: 32, width: 1920, height: 1048}; window.emit('size-changed');
    assert.equal(window.bms_static_blur, true, 'Tiling Assistant tile-to-work-area turns static');
    window.frame = {x: 0, y: 32, width: 960, height: 1048}; window.emit('size-changed');
    assert.equal(window.bms_static_blur, false, 'a half tile turns dynamic again');
});
process.exitCode = failures ? 1 : 0;

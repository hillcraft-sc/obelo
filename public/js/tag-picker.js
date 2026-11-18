// Tag picker for note pages (notes/_tag-picker.ejs). Selected tags show as pills inside the box;
// the dropdown lists the other existing tags, filtered by what's typed. The hidden input named
// "tags" holds the selection as "a, b", which is the format the server already reads.
(function () {
  const normalise = (t) => String(t).trim().toLowerCase().replace(/^#+/, '').trim();

  document.querySelectorAll('[data-tag-picker]').forEach(init);

  function init(root) {
    const all = [...new Set(JSON.parse(root.dataset.all || '[]').map(normalise))];
    let selected = [...new Set(JSON.parse(root.dataset.selected || '[]').map(normalise))].filter(Boolean);
    const hidden = root.querySelector('input[name="tags"]');
    const box = root.querySelector('[data-tag-box]');
    const chips = root.querySelector('[data-tag-chips]');
    const input = root.querySelector('[data-tag-input]');
    const menu = root.querySelector('[data-tag-menu]');
    let options = [];
    let active = -1;

    // Redraws the pills and the hidden value. `userChange` is true only for clicks and typing,
    // so opening a note does not count as an edit and does not trigger autosave.
    function render(userChange) {
      chips.textContent = '';
      selected.forEach((t) => {
        const pill = document.createElement('span');
        pill.className = 'inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs bg-indigo-600/20 text-indigo-200 border border-indigo-500/30';
        pill.append('#' + t);
        const x = document.createElement('button');
        x.type = 'button';
        x.title = 'Remove tag';
        x.textContent = '×';
        x.className = 'text-indigo-300 hover:text-white leading-none';
        x.addEventListener('click', (e) => { e.stopPropagation(); remove(t); });
        pill.append(x);
        chips.append(pill);
      });
      hidden.value = selected.join(', ');
      if (userChange) hidden.dispatchEvent(new Event('change', { bubbles: true }));
    }

    function buildOptions() {
      const q = normalise(input.value);
      const free = all.filter((t) => !selected.includes(t) && (!q || t.includes(q)));
      options = free.slice(0, 50).map((t) => ({ label: '#' + t, value: t }));
      if (q && !all.includes(q) && !selected.includes(q)) {
        options.unshift({ label: 'Create #' + q, value: q, create: true });
      }
      active = options.length ? 0 : -1;
    }

    function drawMenu() {
      menu.textContent = '';
      if (options.length === 0) {
        const empty = document.createElement('p');
        empty.className = 'px-3 py-2 text-xs text-gray-500';
        empty.textContent = all.length ? 'No matching tags. Press Enter to create one.' : 'No tags yet. Type one and press Enter.';
        menu.append(empty);
      }
      options.forEach((opt, i) => {
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.textContent = opt.label;
        btn.className = 'block w-full text-left px-3 py-1.5 text-sm '
          + (i === active ? 'bg-gray-800 text-white' : 'text-gray-300 hover:bg-gray-800')
          + (opt.create ? ' italic' : '');
        // mousedown keeps focus in the input; the click does the work
        btn.addEventListener('mousedown', (e) => e.preventDefault());
        btn.addEventListener('click', () => add(opt.value));
        menu.append(btn);
      });
    }

    function openMenu() {
      buildOptions();
      drawMenu();
      menu.classList.remove('hidden');
    }
    function closeMenu() { menu.classList.add('hidden'); }

    function add(tag) {
      const t = normalise(tag);
      if (t && !selected.includes(t)) selected.push(t);
      input.value = '';
      render(true);
      openMenu();
      input.focus();
    }

    function remove(tag) {
      selected = selected.filter((t) => t !== tag);
      render(true);
      if (menu.classList.contains('hidden')) return;
      openMenu();
    }

    box.addEventListener('click', () => input.focus());
    input.addEventListener('focus', openMenu);
    input.addEventListener('input', openMenu);

    input.addEventListener('keydown', (e) => {
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        if (menu.classList.contains('hidden')) openMenu();
        if (options.length) {
          active = (active + (e.key === 'ArrowDown' ? 1 : -1) + options.length) % options.length;
          drawMenu();
        }
      } else if (e.key === 'Enter' || e.key === ',') {
        e.preventDefault();
        if (active >= 0 && options[active]) add(options[active].value);
        else if (normalise(input.value)) add(input.value);
      } else if (e.key === 'Backspace' && input.value === '' && selected.length) {
        remove(selected[selected.length - 1]);
      } else if (e.key === 'Escape') {
        closeMenu();
        input.blur();
      }
    });

    document.addEventListener('click', (e) => {
      if (!root.contains(e.target)) closeMenu();
    });

    render(false);
  }
})();

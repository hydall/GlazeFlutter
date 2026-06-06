export function createImageAttachment(src, hidden, icon) {
  const wrap = document.createElement('div');
  wrap.className = 'msg-image-attachment' + (hidden ? ' image-hidden' : '');

  const img = document.createElement('img');
  img.src = src;
  img.alt = 'attachment';
  img.loading = 'lazy';
  wrap.appendChild(img);

  const toggle = document.createElement('div');
  toggle.className = 'image-ctx-toggle';
  toggle.dataset.action = 'toggle-image-hidden';
  toggle.innerHTML = hidden ? icon.hidden : icon.eye;
  wrap.appendChild(toggle);

  return wrap;
}

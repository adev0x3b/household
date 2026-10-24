// The page's CSRF token (csrf_meta_tags in the layout), for a request a
// controller sends itself with fetch or XMLHttpRequest — Turbo adds it to
// the ones it sends.
export function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content
}

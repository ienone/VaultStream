// Flutter 3.47's SemanticIncrementable labels the wrapper, but its focusable
// range input has no name. Link to that existing label; leave values, focus,
// keyboard and pointer handling to Flutter. Remove when the engine does this.
(() => {
  const selector = 'flt-semantics > input[type="range"][role="slider"]';
  const linkedInputs = new WeakSet();

  function linkInput(input) {
    const parent = input.parentElement;
    const label = parent.getAttribute('aria-label');
    if (linkedInputs.has(input) && (!label || input.hasAttribute('aria-label'))) {
      if (input.getAttribute('aria-labelledby') === parent.id) {
        input.removeAttribute('aria-labelledby');
      }
      linkedInputs.delete(input);
    }
    if (label && parent.id && !input.hasAttribute('aria-label') &&
        !input.hasAttribute('aria-labelledby')) {
      input.setAttribute('aria-labelledby', parent.id);
      linkedInputs.add(input);
    }
  }

  function linkTree(root) {
    if (!(root instanceof Element)) return;
    if (root.matches(selector)) linkInput(root);
    root.querySelectorAll(selector).forEach(linkInput);
  }

  new MutationObserver((changes) => {
    for (const change of changes) {
      if (change.type === 'attributes') {
        linkTree(change.target);
      } else {
        change.addedNodes.forEach(linkTree);
      }
    }
  }).observe(document.body, {
    childList: true, subtree: true, attributes: true, attributeFilter: ['aria-label'],
  });
  linkTree(document.body);
})();

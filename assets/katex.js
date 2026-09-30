const init =  async function(app) {

  console.log("I am starting elm-katex: init");
  var katexJs = document.createElement('script')
  katexJs.type = 'text/javascript'
  katexJs.onload = function() {
    console.log("elm-katex: katex loading");
    initKatex();
    console.log("elm-katex: mhchem loading");
    loadMhchem();
  }
  katexJs.src = "https://cdn.jsdelivr.net/npm/katex@0.12.0/dist/katex.min.js"

  function loadMhchem() {
    var mhChemJs = document.createElement('script');
    mhChemJs.type = 'text/javascript';
    mhChemJs.onload = function() {
      console.log("elm-katex: mhchem loaded");
    };
    mhChemJs.src = "https://cdn.jsdelivr.net/npm/katex@0.12.0/dist/contrib/mhchem.min.js";

    document.head.appendChild(mhChemJs);
    console.log("elm-katex: I have appended mhChemJs to document.head");
  }

  document.head.appendChild(katexJs);
  console.log("elm-katex: I have appended katexJs to document.head");

}

function initKatex() {

  console.log("elm-katex: initializing");

  // v3 keeps math-text nodes across edits and updates their `content` and
  // `display` properties, so render on property changes, not only on connect.
  class MathText extends HTMLElement {

    constructor() {
      super();
      this.attachShadow({mode: "open"});
    }

    connectedCallback() {
      // Elm may set properties before the element is upgraded
      this._upgradeProperty('content');
      this._upgradeProperty('display');
      this._render();
    }

    _upgradeProperty(prop) {
      if (Object.prototype.hasOwnProperty.call(this, prop)) {
        let value = this[prop];
        delete this[prop];
        this[prop] = value;
      }
    }

    set content(val) {
      this._content = val;
      if (this.isConnected) this._render();
    }
    get content() { return this._content; }

    set display(val) {
      this._display = val;
      if (this.isConnected) this._render();
    }
    get display() { return this._display; }

    _render() {
      this.shadowRoot.innerHTML =
        katex.renderToString(
          this._content || '',
          { throwOnError: false, displayMode: this._display || false }
        );
      let link = document.createElement('link');
      link.setAttribute('rel', 'stylesheet');
      link.setAttribute('href', 'https://cdn.jsdelivr.net/npm/katex@0.12.0/dist/katex.min.css');
      this.shadowRoot.appendChild(link);
    }

  }

  customElements.define('math-text', MathText)

}
'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"assets/AssetManifest.bin": "7bc9af8b3e4b7a721949e70ace3a0cf6",
"assets/AssetManifest.bin.json": "185b3ddcc941526bf77a17fb8c8ce2fe",
"assets/AssetManifest.json": "c3945db0c3fb2b719715dbe3d6a07bfc",
"assets/FontManifest.json": "dc3d03800ccca4601324923c0b1d6d57",
"assets/fonts/MaterialIcons-Regular.otf": "2d4f584ed0bd9a1491a2b4d574ea6d9d",
"assets/images/battle.png": "7f759d4fd9c32d3fbbd331f8ce1a680c",
"assets/images/Cura.png": "81e37951f1611aea1902d68c17aa1a93",
"assets/images/Ellipse%25201.png": "ff373f02c0b043bdd65f56e3f877e056",
"assets/images/Francy.png": "a165ea225db9ef57badb131a18835898",
"assets/images/icons/Cura.svg": "309d0bfc88ca75bc95180369110bbc36",
"assets/images/icons/Fisico.png": "103e77fe9eb4ebde656f79229117c416",
"assets/images/icons/Speciale.png": "7d934491885a9b54406ec122ec8830d9",
"assets/images/icons/tipi/Acciaio.png": "ec597e376ffbd2977130aa5a53c04a23",
"assets/images/icons/tipi/Acqua.png": "3fea23107253868aed405e32e54aa750",
"assets/images/icons/tipi/Acqua_2.png": "c5d91caabb012daa1aa368c1d4651bd6",
"assets/images/icons/tipi/Buio.png": "e74a335e805e585372c313643d0e649d",
"assets/images/icons/tipi/Coleottero.png": "34cbf9d46d552dd9540952c30ca7723a",
"assets/images/icons/tipi/Drago.png": "7e6f212dfd636c8db6d1761b65bc7f39",
"assets/images/icons/tipi/Elettro.png": "e495bcf4e3e5fc694089a150e27ad95f",
"assets/images/icons/tipi/Erba.png": "66b5d6463ef7fd710a8d965a9f280671",
"assets/images/icons/tipi/Folletto.png": "052b4b9487f349ee341dda10d8c91242",
"assets/images/icons/tipi/Fuoco.png": "52834316173adb847de839da22828ec6",
"assets/images/icons/tipi/Fuoco_2.png": "ec3c3414dc2e8612a910c42adbd28d47",
"assets/images/icons/tipi/Fuoco_3.png": "95658a6072c0bb2d5ccffc15521d1508",
"assets/images/icons/tipi/Ghiaccio.png": "ffc382061b052ca1963ec34c5cea7be5",
"assets/images/icons/tipi/Ghiaccio_3.png": "29c33f061b73cf77292be983fca1b541",
"assets/images/icons/tipi/Lotta.png": "4390036b415a8ff1b5685c9faa862a6b",
"assets/images/icons/tipi/Normale.png": "b5137c4b006c6f037b687b6ae97aaddb",
"assets/images/icons/tipi/Psico.png": "2657393729fdd8a1abdbc7d08db55885",
"assets/images/icons/tipi/Roccia.png": "824b4d7e5064bfe025ffe993be498222",
"assets/images/icons/tipi/Spettro.png": "6f206268cb32164d4466750b0bdb05aa",
"assets/images/icons/tipi/Terra.png": "5728780a93e5b7000308f47085c8ffea",
"assets/images/icons/tipi/Veleno.png": "9110e28064c519d422c948b1c2fbacc6",
"assets/images/icons/tipi/Volante.png": "029ccd0cbf2b57a4514029bf48fd9baa",
"assets/images/images.png": "9db532fa7c7a5cf6d41b0dc7843f37f0",
"assets/images/party.png": "1e6ab064a9434332e4e3f28c4a57228b",
"assets/images/Rect2.png": "416343b9319c56a95827cb4b0b805bab",
"assets/images/Selfenid.png": "00f8ac45e0cef5b71eaceb39609ce4eb",
"assets/images/Selfenid_Old.png": "8e719482a5ae5b30474b52d5ee9472a2",
"assets/images/stats.png": "6fba4baba240d095f1556e4180e91a30",
"assets/images/tab_clip.png": "eda758df647a3d4de6942b47cd702ae1",
"assets/images/tab_clip_2.png": "af522bb2086ba838dbd3e85c139b76ae",
"assets/NOTICES": "52878fd906fbb8a4b680c597eaf3109d",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"canvaskit/canvaskit.js": "140ccb7d34d0a55065fbd422b843add6",
"canvaskit/canvaskit.js.symbols": "58832fbed59e00d2190aa295c4d70360",
"canvaskit/canvaskit.wasm": "07b9f5853202304d3b0749d9306573cc",
"canvaskit/chromium/canvaskit.js": "5e27aae346eee469027c80af0751d53d",
"canvaskit/chromium/canvaskit.js.symbols": "193deaca1a1424049326d4a91ad1d88d",
"canvaskit/chromium/canvaskit.wasm": "24c77e750a7fa6d474198905249ff506",
"canvaskit/skwasm.js": "1ef3ea3a0fec4569e5d531da25f34095",
"canvaskit/skwasm.js.symbols": "0088242d10d7e7d6d2649d1fe1bda7c1",
"canvaskit/skwasm.wasm": "264db41426307cfc7fa44b95a7772109",
"canvaskit/skwasm_heavy.js": "413f5b2b2d9345f37de148e2544f584f",
"canvaskit/skwasm_heavy.js.symbols": "3c01ec03b5de6d62c34e17014d1decd3",
"canvaskit/skwasm_heavy.wasm": "8034ad26ba2485dab2fd49bdd786837b",
"favicon.png": "5dcef449791fa27946b3d35ad8803796",
"flutter.js": "888483df48293866f9f41d3d9274a779",
"flutter_bootstrap.js": "8faa34d09a20152ebee2d69e6e421078",
"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"index.html": "afefcf98d77a49a6907f4eb3b1d991ae",
"/": "afefcf98d77a49a6907f4eb3b1d991ae",
"main.dart.js": "7e1581959dc03730f96495f4be6a135d",
"manifest.json": "9868000e6a0f1e0deb425306b813d138",
"version.json": "e974d0c442f729996688b7fa4426947a"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}

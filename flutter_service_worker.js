'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"assets/AssetManifest.bin": "18907428956b9b3374c1a9e79acc51ef",
"assets/AssetManifest.bin.json": "eaa3256519a0b919a6b5e19877472285",
"assets/AssetManifest.json": "98de4048a7868fb56cc52c6d668d0457",
"assets/FontManifest.json": "dc3d03800ccca4601324923c0b1d6d57",
"assets/fonts/MaterialIcons-Regular.otf": "004a349d641b8c2754ab2776b812b29f",
"assets/images/battle.png": "7f759d4fd9c32d3fbbd331f8ce1a680c",
"assets/images/Cura.png": "81e37951f1611aea1902d68c17aa1a93",
"assets/images/Erayka.png": "c2611cc2f6622afefcbe764b2c186332",
"assets/images/flame3.png": "4d4281816bfa25cb58b749b7436773ff",
"assets/images/Fragtz.png": "fba5b1e6285fd7aabe3fc3e08b89f471",
"assets/images/Francy.png": "a165ea225db9ef57badb131a18835898",
"assets/images/icons/Cura.svg": "309d0bfc88ca75bc95180369110bbc36",
"assets/images/icons/Fisico.png": "d3e8965f92c0213291b28059d097d7e2",
"assets/images/icons/Speciale.png": "7d934491885a9b54406ec122ec8830d9",
"assets/images/icons/tipi/Acciaio.png": "ec597e376ffbd2977130aa5a53c04a23",
"assets/images/icons/tipi/Acqua.png": "3fea23107253868aed405e32e54aa750",
"assets/images/icons/tipi/Buio.png": "737b269d8766bc7cddb75655407fce2b",
"assets/images/icons/tipi/Coleottero.png": "34cbf9d46d552dd9540952c30ca7723a",
"assets/images/icons/tipi/Drago.png": "012d121df259a203a7f7a99119731d3a",
"assets/images/icons/tipi/Elettro.png": "4e5e4e392c9e74d6c514c0891bf1a3ca",
"assets/images/icons/tipi/Erba.png": "cdcc5e629a2900154a7a8f1a53766209",
"assets/images/icons/tipi/Folletto.png": "052b4b9487f349ee341dda10d8c91242",
"assets/images/icons/tipi/Fuoco.png": "52834316173adb847de839da22828ec6",
"assets/images/icons/tipi/Fuoco_3.png": "95658a6072c0bb2d5ccffc15521d1508",
"assets/images/icons/tipi/Ghiaccio.png": "ffc382061b052ca1963ec34c5cea7be5",
"assets/images/icons/tipi/Lotta.png": "b7e456d34aafbab786cfd159b722e941",
"assets/images/icons/tipi/Normale.png": "b5137c4b006c6f037b687b6ae97aaddb",
"assets/images/icons/tipi/Psico.png": "d582b90dba9df8f38db42c25905cbe4e",
"assets/images/icons/tipi/Spettro.png": "6f206268cb32164d4466750b0bdb05aa",
"assets/images/icons/tipi/Terra.png": "ce0095c5a21ed54c14c82eb3baae2dd6",
"assets/images/icons/tipi/Veleno.png": "9110e28064c519d422c948b1c2fbacc6",
"assets/images/icons/tipi/Volante.png": "029ccd0cbf2b57a4514029bf48fd9baa",
"assets/images/JJ.png": "a65f7e553e825e1427023b4281236e00",
"assets/images/Lilya.png": "6f978c827bbb31b07ab553b0af3342ea",
"assets/images/party.png": "1e6ab064a9434332e4e3f28c4a57228b",
"assets/images/Selfenid.png": "00f8ac45e0cef5b71eaceb39609ce4eb",
"assets/images/Selfenid2.png": "7e38c88b4c209d4983c0146a03405a29",
"assets/images/Selfenid_Old.png": "8e719482a5ae5b30474b52d5ee9472a2",
"assets/images/stats.png": "6fba4baba240d095f1556e4180e91a30",
"assets/images/Teo.png": "abf8beb9702d0fc62879ed3c634d90d8",
"assets/NOTICES": "2648a07a5a4b882ce10a3e5c44146b32",
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
"flutter_bootstrap.js": "dc8b2d958bae50c0d92fa18c8f954ce5",
"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"index.html": "afefcf98d77a49a6907f4eb3b1d991ae",
"/": "afefcf98d77a49a6907f4eb3b1d991ae",
"main.dart.js": "e196eef67601bfa8b3cfaffff8906e7b",
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

package lix.client;

import lix.client.sources.*;
import haxe.DynamicAccess;
import lix.client.Archives;

using sys.FileSystem;
using sys.io.File;

using haxe.Json;

class Client {
  
  public var scope(default, null):Scope;
  
  var urlToJob:Url->Promise<ArchiveJob>;
  public var log(default, null):String->Void;

  public function new(scope, urlToJob, log) {
    this.scope = scope;
    this.urlToJob = urlToJob;
    this.log = log;
  }
  
  static public function downloadArchiveInto(?kind:ArchiveKind, url:Url, tmpLoc:String):Promise<DownloadedArchive> 
    return (switch kind {
      case null: Download.archive(url, 0, tmpLoc);
      case Zip: Download.zip(url, 0, tmpLoc);
      case Tar: Download.tar(url, 0, tmpLoc);
    }).next(function (dir:String) {
      return new DownloadedArchive(url, dir);
    });

  public function downloadUrl(url:Url, ?into:String, ?as:LibVersion) 
    return download(urlToJob(url), into, as);
    
  public function download(a:Promise<ArchiveJob>, ?into:String, ?as:LibVersion) 
    return a.next(
      function (a) {
        log('downloading ${a.url}');
        return downloadArchiveInto(a.kind, a.url, scope.haxeshimRoot + '/downloads/download@'+Date.now().getTime())
          .next(function (res) {
            return res.saveAs(scope.libCache, switch into {
              case null: 
                switch a.dest {
                  case Some(v): v;
                  default: null;
                }
              case v: v;
            }, as);
          });      
      });

  public function installUrl(url:Url, ?as:LibVersion):Promise<Noise>
    return install(urlToJob(url), as);
    
  public function install(a:Promise<ArchiveJob>, ?as:LibVersion):Promise<Noise> 
    return download(a).next(function (a) {
      var extra =
        switch '${a.absRoot}/extraParams.hxml' {
          case found if (found.exists()):
            found.getContent();
          default: '';
        }
        
      var hxml = Resolver.libHxml(scope.scopeLibDir, a.infos.name);
      
      Fs.ensureDir(hxml);
      
      // var target = '';
      // switch a.savedAs {
      //   case Some(v): 'as ' + v.toString();
      //   case None: '';
      // }

      // log('mounting as $target');  
      
      var haxelibs:DynamicAccess<String> = null;

      var deps = 
        switch '${a.absRoot}/haxelib.json' {
          case found if (found.exists()):
            haxelibs = found.getContent().parse().dependencies;
            [for (name in haxelibs.keys()) '-lib $name'];
          default: [];
        }
      
      hxml.saveContent([
        '# @install: lix download ${a.source.toString()} into ${a.location}',
        '-D ${a.infos.name}=${a.infos.version}',
        '-cp $${HAXESHIM_LIBCACHE}/${a.relRoot}/${a.infos.classPath}',
        extra,
      ].concat(deps).join('\n'));
      
      return 
        switch haxelibs {
          case null: Noise;
          default:
            Haxelib.installDependencies(haxelibs, this, function (s) return '${scope.scopeLibDir}/$s.hxml'.exists());
        }
    });
  
}
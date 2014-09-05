<?

class S2Context {

    private $layers = NULL;
    private $functable = NULL;
    private $properties = array();

    function __construct($layers) {
        
        $this->functable = array();
        $this->layers = &$layers;

        foreach ($layers as &$layer) {
            if (! is_object($layer)) $layer = new S2Layer($layer);
            
            foreach ($layer->getFunctionTable() as $name => $key) {
                $this->functable[$name] = $layer->getFunctionSourceFile($key);
            }
        }
    }
    
    private function is_object_defined($obj) {
        return (is_array($obj) && isset($obj["_type"]));
    }
    
    private function call_function($name, $funcargs) {
        if (! isset($this->functable[$name])) throw new Exception("Function $name does not exist in context");
        $sourcefile = $this->functable[$name];
        $locals = array();
        return require($sourcefile);
    }
    
    private function call_method($object, $method, $apparentclass, $issuper, $args) {

        if (! $this->is_object_defined($object)) {
            throw new Exception("Called $method on undefined $apparentclass object");
        }

        if ($issuper) {
            $realname = $apparentclass."::".$method;
        }
        else {
            $realname = $object["_type"]."::".$method;
        }
        return $this->call_function($realname, $args);
    }
    
    function run($funcname, $args = array()) {
        return $this->call_function($funcname, $args);
    }
    
    function runMethod($object, $methname, $args = array()) {
        return $this->call_method($object, $methname, $object["_type"], 0, array_merge(array($object), $args));
    }

}

class S2Layer {

    private $dir = NULL;
    private $functable = NULL;
    private $layerinfo = NULL;
    private $propset = NULL;
    private $properties = NULL;
    private $classes = NULL;

    function __construct($dir) {
        if (! is_dir($dir)) {
            throw new Exception("Directory $dir does not exist");
        }
        if (substr($dir, -1) == "/" || substr($dir, -1) == "\\") {
            $dir = substr($dir, 0, -1);
        }
        if (! is_file($dir."/functable.php")) {
            throw new Exception("Directory $dir does not contain an S2 layer");
        }
        $this->dir = $dir;
    }
    
    private function ourFile($path) {
        return $this->dir."/".$path;
    }
    
    private function runOurFile($path) {
        return require($this->dir."/".$path);
    }
    
    function getFunctionTable() {
        if (isset($this->functable)) return $this->functable;
        
        return $this->functable = $this->runOurFile("functable.php");
    }
    
    function getFunctionSourceFile($key) {
        return $this->ourFile("func/${key}.php");
    }

}

?>

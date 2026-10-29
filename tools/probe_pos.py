"""Run the upstream inference methods without installing a Python NLP runtime."""
import ast
import collections
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
source=ast.parse((ROOT/'sources/nlp/perceptron.py').read_text())
cls=next(n for n in source.body if isinstance(n,ast.ClassDef) and n.name=='PerceptronTagger')
methods=[n for n in cls.body if isinstance(n,ast.FunctionDef) and n.name in {'normalize','_get_features','tag'}]
namespace={'defaultdict':collections.defaultdict}
exec(compile(ast.fix_missing_locations(ast.Module(body=methods,type_ignores=[])),str(ROOT/'sources/nlp/perceptron.py'),'exec'),namespace)

def reference():
    model=ROOT/'sources/nlp/averaged_perceptron_tagger_eng'
    weights=json.loads((model/'averaged_perceptron_tagger_eng.weights.json').read_text())
    classes=json.loads((model/'averaged_perceptron_tagger_eng.classes.json').read_text())
    class Predictor:
        def predict(self,features,return_conf=False):
            scores=collections.defaultdict(float)
            for feature,value in features.items():
                for label,weight in weights.get(feature,{}).items():scores[label]+=value*weight
            return max(classes,key=lambda label:(scores[label],label)),None
    tagger=type('Reference',(),{name:namespace[name] for name in ('normalize','_get_features','tag')})()
    tagger.START=['-START-','-START2-'];tagger.END=['-END-','-END2-']
    tagger.tagdict=json.loads((model/'averaged_perceptron_tagger_eng.tagdict.json').read_text())
    tagger.model=Predictor()
    return tagger

if __name__=='__main__':
    tagger=reference()
    for text in ['Harry Potter met Hermione Granger .','The potter made a clay bowl .',
                 'Potter made a clay bowl .','I saw Harry and Mr. Potter .','Alice said hello to John Smith .',
                 'After dinner , the boy walked home .','HARRY POTTER was at school .',
                 'harry potter was at school .']:
        print(tagger.tag(text.split()))

"
I implement the generic code for a Smalltalk -> AST compiler.

I have subclasses to accept various input formats, notably Pharo ASTs and sourcecode
"
Class {
	#name : #ASCompiler,
	#superclass : #Object,
	#instVars : [
		'classes',
		'methods',
		'selectors',
		'definingClass',
		'definingMethod',
		'currentScope',
		'freeSelectors',
		'methodsAlreadyProcessed',
		'methodsToProcess'
	],
	#classVars : [
		'ClassIndices',
		'ClassMap'
	],
	#category : #'ASTSmalltalk-Compiler'
}

{ #category : #'class initialization' }
ASCompiler class >> initialize [

	ClassIndices := #( Object False True UndefinedObject Symbol Character
	                   SmallInteger Float Array String Class Metaclass
	                   Behavior BlockClosure Method MethodDictionary
	                   System Return Send Literal Load Store SymbolTable
	                   Dispatch ClassTable Magnitude Number ClassDescription
	                   Boolean ).
	ClassMap := Dictionary new.
	ClassMap at: ByteString put: ASTString.
	ClassMap at: ByteString class put: ASTString class.
	ClassMap at: BlockClosure put: ASTBlock.
	ASTObject withAllSubclassesDo: [ :class | 
		(Smalltalk
			 at: (class name allButFirst: 3) asSymbol
			 ifAbsent: [ nil ]) ifNotNil: [ :pharoClass | 
			ClassMap at: pharoClass instanceSide put: class instanceSide.
			ClassMap at: pharoClass classSide put: class classSide ] ]
]

{ #category : #building }
ASCompiler >> addClass: aClass [

	| astClass |
	astClass := ClassMap at: aClass ifAbsent: [ 
		            aClass ].
	(classes includes: astClass) ifTrue: [ ^ astClass ].
	classes add: astClass.
	astClass isClassSide
		ifTrue: [ classes add: astClass instanceSide ]
		ifFalse: [ classes add: astClass classSide ].
	freeSelectors do: [ :selector | 
		self send: selector toClass: astClass ].
	^ astClass
]

{ #category : #building }
ASCompiler >> addMethod: method [
	(methodsAlreadyProcessed includes: method) ifFalse: [
		methodsToProcess add: method ]
]

{ #category : #building }
ASCompiler >> buildFromClass: aClass selector: selector [

	self send: selector toClass: aClass.
	self transitiveClosure
]

{ #category : #building }
ASCompiler >> buildFromClasses: someClasses withSelectors: someSelectors [

	someClasses
		with: someSelectors
		do: [ :aClass :aSelector | self send: aSelector toClass: aClass ].
	self transitiveClosure
]

{ #category : #accessing }
ASCompiler >> classes [

	^ classes collect: #instanceSide
]

{ #category : #compiling }
ASCompiler >> compileMethod: aCompiledMethod [
	^ self subclassResponsibility 
]

{ #category : #accessing }
ASCompiler >> definingClass [
	^ definingClass
]

{ #category : #compiling }
ASCompiler >> definingClass: aClass [

	definingClass := aClass.
	classes add: aClass instanceSide.
	classes add: aClass classSide.
	"currentScope := aClass.
	^ASClassNode new from: aClass"
	currentScope := ASClassNode new from: aClass.
	^currentScope
	
]

{ #category : #accessing }
ASCompiler >> definingMethod [
	^ definingMethod
]

{ #category : #compiling }
ASCompiler >> definingMethod: aMethod [
	definingMethod := aMethod.
	methods add: aMethod
]

{ #category : #building }
ASCompiler >> findClass: aClass [

	| astClass |
	astClass := ClassMap at: aClass ifAbsent: [ aClass ].
	(classes includes: astClass) ifTrue: [ ^ astClass ].
	classes add: astClass.
	astClass isClassSide
		ifTrue: [ classes add: astClass instanceSide ]
		ifFalse: [ classes add: astClass classSide ].
	^ astClass
]

{ #category : #compiling }
ASCompiler >> inScope: anASMethodOrBlock do: aFullBlockClosure [ 
	| savedScope |
	savedScope := currentScope.
	currentScope := anASMethodOrBlock.
	anASMethodOrBlock nestedScopeOf: savedScope. "if we are consistant with setting nestedScope as parent scope do we need a saved scope?"
	aFullBlockClosure ensure: [ currentScope := savedScope ]
]

{ #category : #initialization }
ASCompiler >> initialize [

	super initialize.
	classes := Set new.
	selectors := Set new.
	freeSelectors := Set with: #initialize.
	methods := Set new.
	methodsAlreadyProcessed := Set new.
	methodsToProcess := Set new.
	self addClass: True.
	self addClass: False.
]

{ #category : #inlining }
ASCompiler >> inlineMethods [
	methods do: [ : aMethod |
		ASCheckMethodVisitor new visit: aMethod ]
]

{ #category : #inlining }
ASCompiler >> inlineTraditionalMethods [

	methods do: [ :aMethod | ASCheckTraditionalMethodVisitor new visit: aMethod ]
]

{ #category : #compiling }
ASCompiler >> lookup: aSymbol [
	^ currentScope lookup: aSymbol
]

{ #category : #accessing }
ASCompiler >> methods [
	^ methods
]

{ #category : #building }
ASCompiler >> selector: selector fromClass: aClass [
"Tries to find a method from the given class using the selectors
assumes the aClass is an ASTClass, and will look in its method dictionary.
If the selector does not match any method will look at the classes class for the method.
If non can be found there then look at the superclass.
The last fall back is to look at the class the ast class references and its class side 
for the method."
	^ aClass methodDictionary
		  at: selector
		  ifPresent: [ aClass >> selector ]
		  ifAbsent: [
			  aClass class methodDictionary
				  at: selector
				  ifPresent: [ aClass class >> selector ]
				  ifAbsent: [
					  (ClassMap keyAtValue: aClass ifAbsent: [ nil ])
						  ifNil: [
							  aClass superclass ifNotNil: [ :sc |
								  self selector: selector fromClass: (self addClass: sc) ] ]
						  ifNotNil: [ :originalClass |
							  originalClass methodDictionary
								  at: selector
								  ifPresent: [ originalClass >> selector ]
								  ifAbsent: [
									  originalClass class methodDictionary
										  at: selector
										  ifPresent: [ originalClass class >> selector ] ] ] ] ]
]

{ #category : #accessing }
ASCompiler >> selectors [
	^ selectors
]

{ #category : #building }
ASCompiler >> send: selector toClass: aClass [

	(self selector: selector fromClass: (self addClass: aClass))
		ifNotNil: [ :method |
			selectors add: selector.
			self addMethod: method ]
]

{ #category : #notifying }
ASCompiler >> sent: selector toBlock: anASBlock [

		self send: selector toClass: BlockClosure 
]

{ #category : #notifying }
ASCompiler >> sent: selector toGlobal: string [

		self send: selector toClass: (Smalltalk at: string asSymbol)
]

{ #category : #notifying }
ASCompiler >> sent: selector toLiteral: aLiteral [

	self send: selector toClass: aLiteral class
]

{ #category : #notifying }
ASCompiler >> sent: selector toSelf: unused [

		self send: selector toClass: definingClass
]

{ #category : #notifying }
ASCompiler >> sentToUnknownObject: selector [

	freeSelectors add: selector.
	classes do: [ : aClass | 	self send: selector toClass: aClass ]
]

{ #category : #building }
ASCompiler >> transitiveClosure [

	| toProcess |
	[ methodsToProcess isEmpty ] whileFalse: [
		toProcess := methodsToProcess.
		methodsToProcess := Set new.
		methodsAlreadyProcessed addAll: toProcess.
		toProcess do: [ :method | self compileMethod: method ] ]
]

{ #category : #building }
ASCompiler >> zigString [

	| visitor |
	visitor := ASZigGenerator new compiler: self.
	^ String streamContents: [ :s | 
		  visitor stream: s.
		  methods do: [ :method | visitor visit: method ] ]
]

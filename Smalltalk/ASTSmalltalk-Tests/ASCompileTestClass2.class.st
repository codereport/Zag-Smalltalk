"
I'm a second class to define methods for tests
"
Class {
	#name : #ASCompileTestClass2,
	#superclass : #ASCompileTestClass1,
	#category : #'ASTSmalltalk-Tests-Code'
}

{ #category : #'testing - examples' }
ASCompileTestClass2 >> classVar [
	^ super classVar negated
]

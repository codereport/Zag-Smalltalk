Class {
	#name : #ASAssignmentToken,
	#superclass : #ASSyntax,
	#category : #'ASTSmalltalk-Tokens'
}

{ #category : #parsing }
ASAssignmentToken >> possibleAssign: anASCompiler target: target [

	anASCompiler nextToken.
	^ ASAssign new
		  variable: target
		  expression: (anASCompiler peek assignExpression: anASCompiler)
]

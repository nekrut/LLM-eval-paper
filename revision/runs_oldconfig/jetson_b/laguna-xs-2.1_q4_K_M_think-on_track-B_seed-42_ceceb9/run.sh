#!/usr/bin/env bash
set -euo pipefail

THREADS=${THREADS:-4}
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
REF=data/ref/chrM.fa
RESULTS=results

mkdir -p "$RESULTS"

# Index reference if not already indexed
if [ ! -f "${REF}.bwt" ]; then
    bwa index "$REF"
fi

for sample in $SAMPLES; do
    bam="$RESULTS/${sample}.bam"
    vcf="$RESULTS/${sample}.vcf.gz"
    
    # Skip if all outputs exist (idempotency)
    if [ -f "$bam" ] && [ -f "${bam}.bai" ] && [ -f "$vcf" ]; then
        continue
    fi
    
    # Align and sort BAM
    bwa mem -t $THREADS "$REF" data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
        samtools sort -@ $THREADS -o "$bam" -
    
    samtools index "$bam"
    
    # Variant calling with lofreq (optimized for amplicon data)
    lofreq call -f "$vcf" --ref "$REF" "$bam"
done

# Generate collapsed.tsv from all VCFs
echo -e "sample\tchrom\tpos\tref\talt\taf" > "$RESULTS/collapsed.tsv"

for sample in $SAMPLES; do
    vcf="$RESULTS/${sample}.vcf.gz"
    
    # Extract variant info and add sample name
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AF]\n' "$vcf" | \
        awk -v s="$sample" 'BEGIN{OFS="\t"} {print s, $1, $2, $3, $4, $5}' >> "$RESULTS/collapsed.tsv"
done
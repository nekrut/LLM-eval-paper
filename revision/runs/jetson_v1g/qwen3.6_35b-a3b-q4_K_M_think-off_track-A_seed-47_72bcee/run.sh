#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"

mkdir -p results

# Step 2: Reference indexing (idempotent)
if [ ! -f "data/ref/chrM.fa.fai" ] || [ ! -f "data/ref/chrM.fa.bwt" ]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

# Step 3-5: Alignment, Sorting, Indexing (per sample)
for sample in "${SAMPLES[@]}"; do
    bam="results/${sample}.bam"
    bai="${bam}.bai"
    
    if [ ! -f "$bai" ] || [ "data/raw/${sample}_1.fq.gz" -nt "$bai" ]; then
        bwa mem -t $THREADS \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" | \
        samtools sort -@ $THREADS -o "$bam" -
        
        samtools index -@ $THREADS "$bam"
    fi
done

# Step 6-7: Variant calling, Compression, Indexing (per sample)
for sample in "${SAMPLES[@]}"; do
    vcf="results/${sample}.vcf"
    vcf_gz="${vcf}.gz"
    tbi="${vcf_gz}.tbi"
    
    if [ ! -f "$tbi" ] || [ "results/${sample}.bam" -nt "$tbi" ]; then
        lofreq call-parallel --pp-threads $THREADS --verbose \
            --ref "$REF" \
            --out "$vcf" \
            --sig \
            --bonf \
            "$bam"
            
        bgzip -c "$vcf" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        
        rm -f "$vcf"
    fi
done

# Step 8: Collapse VCFs into TSV (idempotent)
collapsed="results/collapsed.tsv"
need_collapse=false

for sample in "${SAMPLES[@]}"; do
    if [ ! -f "results/${sample}.vcf.gz.tbi" ]; then
        need_collapse=true
        break
    fi
done

if [ "$need_collapse" = true ] || [ ! -f "$collapsed" ]; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz"
        done
    } > "$collapsed"
fi